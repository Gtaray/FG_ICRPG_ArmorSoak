-- 
-- Please see the license.html file included with this distribution for 
-- attribution and copyright information.
--

local fApplyDamageToTarget;

function onInit() 
    fApplyDamageToTarget = ActionEffort.applyDamageToTarget;
    ActionEffort.applyDamageToTarget = applyDamageWithSoak;
end

------------------------------------------------------
-- Handling setting SOAK amount when PC takes damage
------------------------------------------------------
function applyDamageWithSoak(rSource, rTarget, bSecret, rDamageOutput)
    local nDmg, nRemainder = fApplyDamageToTarget(rSource, rTarget, bSecret, rDamageOutput);

    -- We ONLY calculate soak if the damage is to the default health resource
    -- Any other solution would be madness
    local bDoSoak = false;
    for _,sRes in ipairs(rDamageOutput.aHealthResources) do
        if sRes:lower() == DataCommon.health_resource_default then
            bDoSoak = true;
        end
    end

    -- Don't set SOAK when healed, or when the damage is DRAIN
    if bDoSoak and not rDamageOutput.bHeal and not rDamageOutput.bDrain then
        local nSoakBonus = ActorManagerICRPG.getStat(rTarget, "soak");
        local _, nSoakMod, nEffectCount = EffectManagerICRPG.getEffectsBonus(rTarget, "SOAK", false);
        if nEffectCount > 0 then
            nSoakBonus = nSoakBonus + nSoakMod;
        end
        local nAdjustedSoak = math.max(nDmg - nSoakBonus, 0);

        -- Subtract soak and soakbonus
        setSoakAmount(rTarget, nDmg, nRemainder, nAdjustedSoak);
    end
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
    local nBonus = ActorManagerICRPG.getStat(rActor, "soak");
    local nOverflow = DB.getValue(nodeActor, "defense.armor.soak.overflow", 0);
    local nLimit = DB.getValue(nodeActor, "defense.armor.soak.limit", 0);

    local _, nSoakMod, nEffectCount = EffectManagerICRPG.getEffectsBonus(rActor, "SOAK", false);
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
            local nWounds, nMax = ActorManagerICRPG.getHealthResource(rActor);
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
            ActorManagerICRPG.setHealthResource(rActor, nil, nWounds);
            DB.setValue(nodeActor, "defense.armor.damage", "number", nArmorDmg);

            -- Update conditions to reflect changes
            updateConditions(rActor, nWounds, nMax, 0);
            -- Reset SOAK
            setSoakAmount(rActor, 0, 0, 0);
        end
    end
end

function updateConditions(rActor, nCur, nMax, nRemainder)
    local aRes = DataCommon.health_resource[DataCommon.health_resource_default];
    if aRes.conditions then
        aRes.conditions(rActor, nCur, nMax, nRemainder)
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