require "/scripts/util.lua"
require "/quests/scripts/questutil.lua"
require("/quests/scripts/portraits.lua")

function init()
  storage.bdtechEquipped = storage.bdtechEquipped or false
  message.setHandler("techChangeOnBD", function(...) onTechChangeEquippedBD(...) end)
end

function onTechChangeEquippedBD(message, isLocal, techName)
	local eqTech = player.equippedTech("body")
	if eqTech ~= techName then
		storage.bdtechEquipped = techName
		player.makeTechAvailable(techName)
		player.enableTech(techName)
		player.equipTech(techName)
	end
end

function questStart()
	storage.bdtechEquipped = false
end

function questComplete()
	questutil.questCompleteActions()
end

function update(dt)
	if player.equippedTech("body") == storage.bdtechEquipped then
		quest.complete()
	end
end
