# Armor Soak
Extension for the Fantasy Grounds ICRPG ruleset to allow games that use armor to soak damage.

This extension adds the ability for PCs to spend armor to reduce damage taken and tracks the amount of damage a character's armor has soaked.

Due to the nature of the system, damage soaking is done retroactively. So a character will always start by taking full damage. 
The "SOAK" value onf their sheet is then set to however much damage they took.
Then, after the damage is taken, a player may adjust how much armor they want to spend by manually changing the "SOAK" value, then pressing the soak button.
Pressing the button will heal the character for the amount of damage soaked, and deduct that same amount from their armor.

The PC sheet also has a box in the armor soaking section titled "BONUS". Whenever a PC soaks damage with their armor, the amount in that bonus box is added to the amount soaked.
For example, if a character that has a soak bonus of 2 takes 5 damage, then soaks 3 of it with armor, the total damage reduction is 5 (3 from armor, 2 from the bonus).

A new keyword has been added to support the BONUS to soak, called "SOAK".
Loot bonus to this value can be added from items using the text "+# SOAK", and effects can modify it using something like "SOAK: +#".
In the same way, you can also add negative soak values, which increase the cost of absorbing damage.
