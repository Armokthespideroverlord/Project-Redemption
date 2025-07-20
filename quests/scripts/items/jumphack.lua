require "/scripts/util.lua"
require "/quests/scripts/questutil.lua"
require("/quests/scripts/portraits.lua")

function init()
  storage.lgtechEquipped = storage.lgtechEquipped or false
  message.setHandler("techChangeOnLG", function(...) onTechChangeEquippedLG(...) end)
end

function onTechChangeEquippedLG(message, isLocal, techName)
	local eqTech = player.equippedTech("legs")
	if eqTech ~= techName then
		storage.lgtechEquipped = techName
		player.makeTechAvailable(techName)
		player.enableTech(techName)
		player.equipTech(techName)
	end
end

function questStart()
	storage.lgtechEquipped = false
end

function questComplete()
	questutil.questCompleteActions()
end

function update(dt)
	if player.equippedTech("legs") == storage.lgtechEquipped then
		quest.complete()
	end
end
