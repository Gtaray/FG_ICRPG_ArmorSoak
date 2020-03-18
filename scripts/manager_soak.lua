-- 
-- Please see the license.html file included with this distribution for 
-- attribution and copyright information.
--

OOB_MSGTYPE_APPLYDMG = "applydmg";

function onInit() 
    OOBManager.registerOOBMsgHandler(OOB_MSGTYPE_APPLYDMG, handleApplyDamage);
end

------------------------------------------------------
-- Handling setting SOAK amount when PC takes damage
------------------------------------------------------
function handleApplyDamage(msgOOB)
    -- run the effort handler first
    if not msgOOB.sTargetType then return; end
    local rSource = ActorManager.getActor(msgOOB.sSourceType, msgOOB.sSourceNode);
    local rTarget = ActorManager.getActor(msgOOB.sTargetType, msgOOB.sTargetNode);

	if rTarget then
		rTarget.nOrder = msgOOB.nTargetOrder;
    end
    local nDmg = tonumber(msgOOB.nTotal) or 0;
    local bHeal = string.match(msgOOB.sDamage, "%[HEAL%]") or nDmg < 0;

    -- Don't set SOAK when healed
    if not bHeal then
        local nDmg, nRemainder = calculateSoak(rSource, rTarget, msgOOB.sDamage, nDmg)
        local nSoakBonus = ActorManager2.getStat(rTarget, "soak");
        local _, nSoakMod, nEffectCount = EffectManagerICRPG.getEffectsBonus(rTarget, "SOAK", false);
        Debug.chat(nSoakMod);
        if nEffectCount > 0 then
            nSoakBonus = nSoakBonus + nSoakMod;
        end
        local nAdjustedSoak = math.max(nDmg - nSoakBonus, 1);

        -- Subtract soak and soakbonus
        setSoakAmount(rTarget, nDmg, nRemainder, nAdjustedSoak);
    end
    ActionEffort.handleApplyDamage(msgOOB)
end

function calculateSoak(rSource, rTarget, sDesc, nDmg)
    local sTargetType, sTargetNode = ActorManager.getTypeAndNode(rTarget);
    if sTargetType ~= "pc" then return; end
    if not sTargetNode then return; end
    if not nDmg or nDmg < 0 then return; end

    local aNotifications = {};
    local nTotalHP, nWounds;
    nTotalHP = DB.getValue(sTargetNode, "health.hp", 0);
    nWounds = DB.getValue(sTargetNode, "health.wounds", 0);

    local nAdjustedDmg,_,nRemainder = ActionEffort.calculateDamage(rTarget, rSource, sDesc, nDmg, nTotalHP, nWounds, aNotifications);
    return nAdjustedDmg, nRemainder;
end

-- if there is a remainder (i.e. if a character was reduced to 0 hp), we need to calculate the
-- amount of damage that brought the character TO 0 hp. This is important, since soaking damage
-- that would have otherwise brought you to 0 not only needs to account for the damage overflow,
-- but undoing that damage needs to take into account the overflow
-- EXMAPLE: If a PC is at 8 HP and takes 5 damage, SOAKING can't just heal 5, as that results in
-- an end total of 5 WOUNDS, not 8.
function setSoakAmount(rActor, nDmg, nRemainder, nSoak)
    local sActorType, nodeActor = ActorManager.getTypeAndNode(rActor);
    if sActorType ~= "pc" then return; end
    if not nodeActor then return; end
    if not nSoak or nSoak < 0 then return; end
    DB.setValue(nodeActor, "defense.armor.soak.limit", "number", nDmg)
    DB.setValue(nodeActor, "defense.armor.soak.value", "number", nSoak);
    DB.setValue(nodeActor, "defense.armor.soak.overflow", "number", nRemainder);
end

-----------------------------------------------------------------------
-- Handling applying SOAK when the soak button is clicked
-----------------------------------------------------------------------
function applySoak(rActor)
    local sActorType, nodeActor = ActorManager.getTypeAndNode(rActor);
    if not nodeActor then return; end

    local nSoak = DB.getValue(nodeActor, "defense.armor.soak.value", 0);
    local nBonus = ActorManager2.getStat(rActor, "soak");
    local nOverflow = DB.getValue(nodeActor, "defense.armor.soak.overflow", 0);
    local nLimit = DB.getValue(nodeActor, "defense.armor.soak.limit", 0);

    local _, nSoakMod, nEffectCount = EffectManagerICRPG.getEffectsBonus(rActor, "SOAK", false);
    Debug.chat(nSoakMod);
    if nEffectCount > 0 then
        nBonus = nBonus + nSoakMod;
    end

    local nTotalSoak = nSoak + nBonus;
    -- If there's a limit to the soak amount, then clamp the value by that much.
    if nLimit > 0 then
        nTotalSoak = math.min(nTotalSoak, nLimit);
    end

    -- If soak is less than damage, print a message in chat, but don't actually reduce armor
    -- since there's no reason to soak this amount.
    if nTotalSoak <= nOverflow then
        ChatManager.SystemMessage("You must soat at least " .. (nOverflow + 1) .. " damage.");
        return;
    else
        -- Use nSoak and not nTotalSoak because the base value needs to be above 0, not the total
        if nSoak > 0 then
            -- Adjusted SOAK is the amount to heal the PC
            local nHealAmount = nTotalSoak - nOverflow;
            local nWounds = DB.getValue(nodeActor, "health.wounds", 0);
            local nArmorDmg = DB.getValue(nodeActor, "defense.armor.damage", 0);
            local nArmorBase = DB.getValue(nodeActor, "defense.armor.base", 0);
            local nArmorLoot = DB.getValue(nodeActor, "defense.armor.loot", 0);
            local nArmorTotal = nArmorBase + nArmorLoot;
            -- Use nSoak instead of nTotalSoak here because nBonus is not counted
            if nArmorDmg + nSoak > nArmorTotal then
                ChatManager.SystemMessage("Not enough ARMOR to soak " .. nSoak .. " damage.");
                return;
            end

            -- if the soak amount is greature than our wounds, change it
            if nHealAmount > nWounds then
                nHealAmount = nWounds;
            end
            if nHealAmount > nArmorTotal then
                nHealAmount = nArmorTotal;
            end
            nWounds = nWounds - nHealAmount;
            -- Don't use TotalSoak here since we only add the base value that was soaked, not the 
            -- amount added on from bonuses/modifiers/effects
            nArmorDmg = nArmorDmg + nSoak;

            messageSoak(rActor, nSoak, nTotalSoak, nHealAmount, false);
            
            -- Update health and armor dmg in DB
            DB.setValue(nodeActor, "health.wounds", "number", nWounds);
            DB.setValue(nodeActor, "defense.armor.damage", "number", nArmorDmg);

            -- Update conditions to reflect changes
            updateConditions(rActor);
            -- Reset SOAK
            setSoakAmount(rActor, 0, 0, 0);
        end
    end
end

function updateConditions(rActor)
    local sActorType, nodeActor = ActorManager.getTypeAndNode(rActor);
    if not nodeActor then return; end
    local nTotalHP, nWounds;
    nTotalHP = DB.getValue(nodeActor, "health.hp", 0);
    nWounds = DB.getValue(nodeActor, "health.wounds", 0);

    if EffectManagerICRPG.hasCondition(rActor, "Stable") then
        EffectManager.removeEffect(ActorManager.getCTNode(rActor), "Stable");
    end
    if EffectManagerICRPG.hasCondition(rActor, "Dead") then
        EffectManager.removeEffect(ActorManager.getCTNode(rActor), "Dead");
    end
    if nWounds < nTotalHP then
		if EffectManagerICRPG.hasCondition(rActor, "Dying") then
			EffectManager.removeEffect(ActorManager.getCTNode(rActor), "Dying");
		end
	else
		if not EffectManagerICRPG.hasCondition(rActor, "Dying") then
			EffectManager.addEffect("", "", ActorManager.getCTNode(rActor), { sName = "Dying", nDuration = 0 }, true);
		end
	end
end

function messageSoak(rActor, nSoak, nTotal, nHeal, bSecret, sExtra)
    if not rActor then
		return;
    end
    
    local rMessage = ChatManager.createBaseMessage(rActor, nil);
    rMessage.icon = "soak"
    rMessage.text = "[SOAK: " .. nSoak .. "] -> [HEAL: " .. nHeal .. "]";
    rMessage.dice = {}
    rMessage.diemodifier = nTotal

    Comm.deliverChatMessage(rMessage);
end