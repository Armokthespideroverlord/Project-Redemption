require "/scripts/behavior.lua"
require "/scripts/pathing.lua"
require "/scripts/util.lua"
require "/scripts/vec2.lua"
require "/scripts/quest/participant.lua"
require "/scripts/relationships.lua"
require "/scripts/actions/dialog.lua"
require "/scripts/actions/movement.lua"
require "/scripts/drops.lua"
require "/scripts/statusText.lua"
require "/scripts/tenant.lua"
require "/scripts/companions/recruitable.lua"

--I made this because I don't want to add .patch to the other mods, this is a way to not need to change the other mods.
--pcall(function()
--	require "/scripts/blshieldmonster_npc_messages.lua"
--	require "/npcs/blshieldnpc.lua"
--end)
--pcall(function()
--	require "/npcs/bmain_npcshields.lua"
--end)

-- Engine callback - called on initialization of entity
orVillagerPoliceInit = init
function init()
  orVillagerPoliceInit()
  script.setUpdateDelta(5)
  
  math.randomseed(util.seedTime())
  self.calledBackup = false --This is to keep track of wether or not the Police NPC has called backup
  self.canCallBackup = math.random(1,9) == 1 --Chance to call Backup, not every police-officer will have the ability to call.
  --2 apear every time, so there is a 20% chance that 1 can call backup and a 1% chance both can call backup.
  self.healthThreshold = math.random(15,55)/100 --At what health percentage the Police calls for backup
  script.setUpdateDelta(5)
  status.addEphemeralEffect("peacekeeperbeamin", 1)--Add the spawning effect
end


-- Engine callback - called on each update
-- Update frequencey is dependent on update delta
orVillagerPoliceUpdate = update
function update(dt)
local species = {"apex","avian","floran","glitch","human","hylotl","novakid"}
  orVillagerPoliceUpdate(dt)
  if not self.calledBackup and self.canCallBackup and status.resourcePercentage("health") < self.healthThreshold then
	local level = world.threatLevel()
	--Villagers call police that is 2 levels below tier, so backup is 1 tier stronger
	level = (level <= 0 and 1) or level
	if math.random(1,2) == 1 then --1 in 2 chance of spawning Coptop team.
		world.spawnNpc({mcontroller.xPosition() + 2, mcontroller.yPosition()}, species[math.random(#species)], "r-heavypeacekeeper", level) 
		world.spawnNpc({mcontroller.xPosition() - 2, mcontroller.yPosition()}, species[math.random(#species)], "r-heavypeacekeeper", level)
	else --Spawn normal police
		world.spawnNpc({mcontroller.xPosition() + 2, mcontroller.yPosition()}, species[math.random(#species)], "r-peacekeeper", level)
		world.spawnNpc({mcontroller.xPosition() - 2, mcontroller.yPosition()}, species[math.random(#species)], "r-peacekeeper", level)
	end
	self.calledBackup = true 
  end
end

function getDamageAbsorption()
	return { status.resource("damageAbsorption"), status.resource("maxDamageAbsorption") }
end