require "/scripts/util.lua"
require("/scripts/vec2.lua")

function initShip()
  animator.setAnimationState("movement","warpInPart1")
  self.ownerKey = config.getParameter("ownerKey")
  vehicle.setPersistent(self.ownerKey)

  self.moveSpeed = config.getParameter("moveSpeed")
  self.airForce = config.getParameter("airForce")
  
  self.movementSettings = config.getParameter("movementSettings")
  self.occupiedMovementSettings = config.getParameter("occupiedMovementSettings")

  self.maxHealth = config.getParameter("maxHealth") or 20
  self.protection = config.getParameter("protection")
  storage.health = storage.health or config.getParameter("health")

  self.driving = false
  self.lastDriver = nil
  
  self.facingDirection = 1

  self.firing = false
  self.firePods = coroutine.create(firePods)

  message.setHandler("store",
      function(_, _, ownerKey)
        if (self.ownerKey and self.ownerKey == ownerKey and self.driving == false) then
          animator.setAnimationState("movement","warpOutPart1")
          animator.playSound("returnvehicle")
          return {storable = true}
        else
          return {storable = false}
        end
      end)
end

function updateShip(dt, driver, moveDir)
  if storage.health <= 0 then
    animator.burstParticleEmitter("damageShards")
    animator.playSound("explode")
    vehicle.destroy()
  end

  if mcontroller.atWorldLimit() then
    vehicle.destroy()
    return
  end
  
 if (animator.animationState("movement") == "invisible") then
    vehicle.destroy()
	return
  end
  
  if driver then
    if self.lastDriver == nil then
      animator.playSound("engineStart")
      animator.setAnimationState("thrust", "on")
    end

    if driver == 0 then
      vehicle.setDamageTeam({type = "passive"})
    else
      vehicle.setDamageTeam(world.entityDamageTeam(driver))
    end
    mcontroller.applyParameters(self.occupiedMovementSettings)
    vehicle.setInteractive(false)
  else
    vehicle.setDamageTeam({type = "passive"})
    animator.setAnimationState("thrust", "off")
    mcontroller.applyParameters(self.movementSettings)
    vehicle.setInteractive(true)
  end
  self.lastDriver = driver

  local driving = vec2.mag(moveDir) > 0.0
  if driving and not self.driving then
    animator.playSound("engineLoop", -1)
  elseif not driving then
    animator.stopAllSounds("engineLoop", 0.5)
  end
  self.driving = driving

  if moveDir[1] ~= 0 then
    self.facingDirection = util.toDirection(moveDir[1])
    animator.setFlipped(moveDir[1] < 0)
  end

  animator.resetTransformationGroup("rotation")
  animator.resetTransformationGroup("frontcannon")
  animator.resetTransformationGroup("backcannon")
  if driver then
    moveDir = vec2.norm(moveDir)
    mcontroller.approachVelocity(vec2.mul(moveDir, self.moveSpeed), self.airForce)

    local tilt = mcontroller.yVelocity() / self.moveSpeed * 0.5
    mcontroller.setRotation(tilt * util.toDirection(moveDir[1]))
    animator.rotateTransformationGroup("rotation", tilt)

    local frontPivot = vec2.mul(animator.partPoint("frontcannon", "rotationCenter"), {self.facingDirection, 1.0})
    animator.rotateTransformationGroup("frontcannon", -tilt, frontPivot)
    local backPivot = vec2.mul(animator.partPoint("backcannon", "rotationCenter"), {self.facingDirection, 1.0})
    animator.rotateTransformationGroup("backcannon", -tilt, backPivot)
  else
    mcontroller.rotate(-mcontroller.rotation() * dt)
  end

  -- Run pod firing coroutine
  local s, result = coroutine.resume(self.firePods)
  if not s then
    error(result)
  end
end

function toggleBlinds()
  if animator.animationState("blinds") == "closed" then
    animator.setAnimationState("blinds", "open")
  elseif animator.animationState("blinds") == "opened" then
    animator.setAnimationState("blinds", "close")
  end
end

function isFiring()
  return self.firing
end

function startFiring()
  self.firing = true
end

function stopFiring()
  self.firing = false
end

-- coroutine for firing pods
function firePods()
  while true do
    local backLoaded = false
    local frontLoaded = false

    if self.firing then
      animator.setAnimationState("frontcannon", "open")
      animator.setAnimationState("backcannon", "open")
      util.wait(0.25)
      
      if self.firing then
        animator.setAnimationState("frontcannon", "load")
        animator.setAnimationState("backcannon", "load")
        backLoaded = true
        frontLoaded = true
        util.wait(0.15)
      end

      while self.firing do
        if frontLoaded then
          animator.setAnimationState("frontcannon", "fire")
          util.wait(0.1)

          local fireOffset = animator.partPoint("frontcannon", "fireOffset")
          world.spawnProjectile("r-capsule", vec2.add(mcontroller.position(), fireOffset), entity.id(), {0, -1}, false)
          animator.burstParticleEmitter("frontMuzzle")
          animator.playSound("fire")
          util.wait(0.2)

          frontLoaded = false
        else
          -- there has to be at least one yield in this loop even when not firing
          coroutine.yield()
        end
        
          animator.setAnimationState("frontcannon", "load")
          frontLoaded = true

        if backLoaded then
          animator.setAnimationState("backcannon", "fire")
          util.wait(0.1)

          local fireOffset = animator.partPoint("backcannon", "fireOffset")
          world.spawnProjectile("r-capsule", vec2.add(mcontroller.position(), fireOffset), entity.id(), {0, -1}, false)
          animator.burstParticleEmitter("backMuzzle")
          animator.playSound("fire")
          util.wait(0.2)

          backLoaded = false
        end

          animator.setAnimationState("backcannon", "load")
          backLoaded = true
      end
      util.wait(0.15)

      animator.setAnimationState("frontcannon", "close")
      animator.setAnimationState("backcannon", "close")

      util.wait(0.15)
    end

    coroutine.yield()
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