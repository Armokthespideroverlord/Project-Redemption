require "/scripts/vec2.lua"
require "/scripts/util.lua"

function init(dt)
  animator.setAnimationState("movement","warpInPart1")
  self.ownerKey = config.getParameter("ownerKey")
  vehicle.setPersistent(self.ownerKey)
 
  self.moveSpeed = config.getParameter("moveSpeed")
  self.airForce = config.getParameter("airForce")
  
  self.minHeight = config.getParameter("minHeight")
  self.maxHeight = config.getParameter("maxHeight")
  self.height = 0
  
  self.movementSettings = config.getParameter("movementSettings")
  self.occupiedMovementSettings = config.getParameter("occupiedMovementSettings")

  self.maxHealth = config.getParameter("maxHealth") or 20
  self.protection = config.getParameter("protection")
  storage.health = storage.health or config.getParameter("health")

  self.facingDirection = 1

  self.firing = false
  self.driving = false
  self.lastDriver = nil
  message.setHandler("store",
      function(_, _, ownerKey)
        if (self.ownerKey and self.ownerKey == ownerKey and self.driving == false) then
		  animator.setAnimationState("movement", "warpOutPart1")
          animator.playSound("returnvehicle")
          return {storable = true}
        else
          return {storable = false}
        end
      end)
end

function update()
  if mcontroller.atWorldLimit() then
    vehicle.destroy()
    return
  end
  
  if (animator.animationState("movement") == "invisible") then
    vehicle.destroy()
	return
  end

  local firing = vehicle.controlHeld("seat", "primaryFire")
  vehicle.setForceRegionEnabled("beam1", firing)
  vehicle.setForceRegionEnabled("beam2", firing)
  vehicle.setForceRegionEnabled("beam3", firing)
  vehicle.setForceRegionEnabled("beam4", firing)
  vehicle.setDamageSourceEnabled("beam", firing)
  animator.setLightActive("tractorbeam", firing)
  if firing then
    if not self.firing then
      animator.playSound("beamStart")
      animator.playSound("beamLoop", -1)
    end
    animator.setAnimationState("beam", "on")
  else
    if self.firing then
      animator.stopAllSounds("beamLoop", 0.25)
    end
    animator.setAnimationState("beam", "off")
  end
  self.firing = firing;
  
  if storage.health <= 0 then
    animator.burstParticleEmitter("damageShards")
    animator.playSound("explode")
    vehicle.destroy()
  end
  
  local driver = vehicle.entityLoungingIn("seat")
  if driver then
    if self.lastDriver == nil then
      animator.playSound("engineStart")
    end

    vehicle.setDamageTeam(world.entityDamageTeam(driver))
    mcontroller.applyParameters(self.occupiedMovementSettings)
    animator.setLightActive("glow", true)
    vehicle.setInteractive(false)
  else
    vehicle.setDamageTeam({type = "passive"})
    mcontroller.applyParameters(self.movementSettings)
    animator.setLightActive("glow", false)
    vehicle.setInteractive(true)
  end
  self.lastDriver = driver

  local moveDir = {0, 0}
  if vehicle.controlHeld("seat", "right") then
    moveDir[1] = moveDir[1] + 1
  end
  if vehicle.controlHeld("seat", "left") then
    moveDir[1] = moveDir[1] - 1
  end
  if vehicle.controlHeld("seat", "up") then
    moveDir[2] = moveDir[2] + 1
  end
  if vehicle.controlHeld("seat", "down") then
    moveDir[2] = moveDir[2] - 1
  end
  if moveDir[1] ~= 0 then
    animator.setFlipped(moveDir[1] < 0)
  end

  local driving = vec2.mag(moveDir) > 0.0
  if driving and not self.driving then
    animator.playSound("engineLoop", -1)
  elseif not driving then
    animator.stopAllSounds("engineLoop", 0.5)
  end
  self.driving = driving

  if driver then
    local start = mcontroller.position()
    local bottom = vec2.add(start, {0, -self.maxHeight * 2.0})
    local ground
    for xOffset = -1, 1 do
      local findGround = world.collisionBlocksAlongLine(vec2.add(start, {xOffset, 0}), vec2.add(bottom, {xOffset, 0}))[1]
      if findGround and (not ground or findGround[2] > ground[2]) then
        ground = findGround
      end
    end

    local groundDist = self.maxHeight * 2.0
    if ground then
      groundDist = world.distance(start, vec2.add(ground, {0, 1}))[2]
    end
    if groundDist > self.maxHeight then
      moveDir[2] = math.min((self.maxHeight - groundDist) / self.maxHeight, moveDir[2])
    end
    if groundDist < self.minHeight then
      moveDir[2] = math.max((self.minHeight - groundDist) / self.minHeight, moveDir[2])
    end

    moveDir = vec2.norm(moveDir)
    mcontroller.approachVelocity(vec2.mul(moveDir, self.moveSpeed), self.airForce)
  end
end

function applyDamage(damageRequest)
  local damage = 0
  if damageRequest.damageType == "Damage" then
    damage = damage + root.evalFunction2("protection", damageRequest.damage, self.protection)
  elseif damageRequest.damageType == "IgnoresDef" then
    damage = damage + damageRequest.damage
  else
    return {}
  end

  local healthLost = math.min(damage, storage.health)
  storage.health = storage.health - healthLost

  return {{
    sourceEntityId = damageRequest.sourceEntityId,
    targetEntityId = entity.id(),
    position = mcontroller.position(),
    damageDealt = damage,
    healthLost = healthLost,
    hitType = "Hit",
    damageSourceKind = damageRequest.damageSourceKind,
    targetMaterialKind = "robotic",
    killed = storage.health <= 0
  }}
end