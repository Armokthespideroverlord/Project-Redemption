require "/scripts/vec2.lua"

function init()
  mcontroller.setRotation(0)

  self.monsterType = config.getParameter("monsterType")
  self.npcType = config.getParameter("npcType")
  self.species = config.getParameter("species")
  self.count = config.getParameter("count", 1)
end

function destroy()
  for i = 1, self.count do
    local entityId
    if self.monsterType then
      entityId = world.spawnMonster(self.monsterType, entity.position(), {level = world.threatLevel()})
    elseif self.npcType then
      entityId = world.spawnNpc(entity.position(), self.species, self.npcType, world.threatLevel())
    else
      error("No monsterType or npcType configured")
    end
    
    world.callScriptedEntity(entityId, "mcontroller.setVelocity", vec2.withAngle(math.random() * math.pi, 20))
  end
end