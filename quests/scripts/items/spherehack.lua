require "/scripts/util.lua"
require "/quests/scripts/questutil.lua"
require("/quests/scripts/portraits.lua")

function init()
  storage.hdtechEquipped = storage.hdtechEquipped or false
  message.setHandler("techChangeOnHD", function(...) onTechChangeEquippedHD(...) end)
end

function onTechChangeEquippedHD(message, isLocal, techName)
	local eqTech = player.equippedTech("head")
	if eqTech ~= techName then
		storage.hdtechEquipped = techName
		player.makeTechAvailable(techName)
		player.enableTech(techName)
		player.equipTech(techName)
	end
end

function questStart()
	storage.hdtechEquipped = false
end

function questComplete()
	questutil.questCompleteActions()
end

function update(dt)
	if player.equippedTech("head") == storage.hdtechEquipped then
		quest.complete()
	end
end
