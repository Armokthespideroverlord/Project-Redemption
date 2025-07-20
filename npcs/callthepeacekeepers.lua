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


orVillagerPoliceInit = init
function init()
  if not orVillagerPoliceInit then return end
  orVillagerPoliceInit()
  script.setUpdateDelta(5)

  math.randomseed(util.seedTime())
  self.calledPolice = false
  self.canCallPolice = math.random(1,config.getParameter("callChanceDenominator", 3)) == 1
  self.healthThreshold = math.random(config.getParameter("callHealthMin", 25),config.getParameter("callHealthMax", 75))/100
end

orVillagerPoliceUpdate = update
function update(dt)
local species = config.getParameter("peacekeeperSpecies")
  if not orVillagerPoliceUpdate then return end
  orVillagerPoliceUpdate(dt)
  local etype = world.entityTypeName(entity.id())
  if not self.typeRead then
	 local etype = world.entityTypeName(entity.id())
	 self.npcTypeCanCallPolice = (string.find(etype,"villager") or string.find(etype,"merchant"))
	 self.typeRead = true
  end
  if self.npcTypeCanCallPolice and config.getParameter("hasPhone", true) then
	  if not self.calledPolice and self.canCallPolice and status.resourcePercentage("health") < self.healthThreshold and status.resource("health") > 0 then
		local level = world.threatLevel()
		level = (level <= 0 and 1) or level
		if config.getParameter("forcePeacekeeperVariant", false) ~= false then
			world.spawnNpc({mcontroller.xPosition() + 2, mcontroller.yPosition()}, config.getParameter("forcePeacekeeperVariantSpecies", "human"), config.getParameter("forcePeacekeeperVariant"), level)
			world.spawnNpc({mcontroller.xPosition() - 2, mcontroller.yPosition()}, config.getParameter("forcePeacekeeperVariantSpecies", "human"), config.getParameter("forcePeacekeeperVariant"), level)
  	elseif math.random(1,4) == 1 then
  		world.spawnNpc({mcontroller.xPosition() + 2, mcontroller.yPosition()}, species[math.random(#species)], "r-heavypeacekeeper", level)
  		world.spawnNpc({mcontroller.xPosition() - 2, mcontroller.yPosition()}, species[math.random(#species)], "r-heavypeacekeeper", level)
		else
			world.spawnNpc({mcontroller.xPosition() + 2, mcontroller.yPosition()}, species[math.random(#species)], "r-peacekeeper", level)
			world.spawnNpc({mcontroller.xPosition() - 2, mcontroller.yPosition()}, species[math.random(#species)], "r-peacekeeper", level)
		end
		self.calledPolice = true
	  end
  end
end
