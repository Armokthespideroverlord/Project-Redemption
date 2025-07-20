require "/scripts/vec2.lua"
require "/scripts/util.lua"

function init(dt)
  animator.setAnimationState("movement","warpInPart1")
  self.ownerKey = config.getParameter("ownerKey")
  vehicle.setPersistent(self.ownerKey)

  self.moveSpeed = config.getParameter("moveSpeed")
  self.groundForce = config.getParameter("groundForce")
  self.jumpSpeed = config.getParameter("jumpSpeed")
  
  self.movementSettings = config.getParameter("movementSettings")
  self.occupiedMovementSettings = config.getParameter("occupiedMovementSettings")

  self.minAngle = config.getParameter("minAngle")
  self.maxAngle = config.getParameter("maxAngle")
  self.fireInterval = config.getParameter("fireInterval")

  self.maxHealth = config.getParameter("maxHealth") or 20
  self.protection = config.getParameter("protection")
  storage.health = storage.health or config.getParameter("health")

  self.driving = false
  self.lastDriver = nil

  self.jumping = false

  self.fireCooldown = 0.0
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

function update(dt)
  self.fireCooldown = self.fireCooldown - dt

  if mcontroller.atWorldLimit() then
    vehicle.destroy()
    return
  end
  
  if (animator.animationState("movement") == "invisible") then
    vehicle.destroy()
	return
  end
  
  if storage.health <= 0 then
    animator.burstParticleEmitter("damageShards")
    animator.playSound("explode")
    vehicle.destroy()
  end
  
  local driver = vehicle.entityLoungingIn("seat")
  if driver then
    if self.lastDriver == nil then
      animator.playSound("engineStart")
      animator.playSound("engineLoop", -1)
    end

    vehicle.setDamageTeam(world.entityDamageTeam(driver))
    mcontroller.applyParameters(self.occupiedMovementSettings)
    vehicle.setInteractive(false)
  else
    animator.stopAllSounds("engineLoop")
    vehicle.setDamageTeam({type = "passive"})
    mcontroller.applyParameters(self.movementSettings)
    vehicle.setInteractive(true)
  end
  self.lastDriver = driver

  local moveDir = 0
  if vehicle.controlHeld("seat", "right") then
    moveDir = moveDir + 1
  end
  if vehicle.controlHeld("seat", "left") then
    moveDir = moveDir - 1
  end
  if not self.jumping and mcontroller.onGround() and vehicle.controlHeld("seat", "jump") then
    self.jumping = true
    mcontroller.setYVelocity(self.jumpSpeed)
  end

  mcontroller.approachXVelocity(moveDir * self.moveSpeed, self.groundForce)

  local aim = vehicle.aimPosition("seat")
  local aimSource = vec2.add(mcontroller.position(), animator.partPoint("cannon", "rotationCenter"))
  local mouseDir = vec2.norm(world.distance(aim, aimSource))
  local clampRange = {math.rad(self.minAngle), math.rad(self.maxAngle)}
  local aimAngle = util.clamp(math.atan(mouseDir[2], math.abs(mouseDir[1])), math.rad(self.minAngle), math.rad(self.maxAngle))
  animator.resetTransformationGroup("cannon")
  animator.rotateTransformationGroup("cannon", aimAngle, animator.partPoint("cannon", "rotationCenter"))
  
  if self.fireCooldown <= 0 and vehicle.controlHeld("seat", "primaryFire") then
    local firePosition = vec2.add(mcontroller.position(), animator.partPoint("cannon", "fireOffset"))
    local aimDir = vec2.withAngle(aimAngle)
    aimDir[1] = aimDir[1] * util.toDirection(mouseDir[1])
    world.spawnProjectile("penguintankround", firePosition, entity.id(), aimDir, false)
    animator.playSound("fire")
    animator.burstParticleEmitter("muzzleFlash")

    self.fireCooldown = self.fireInterval
  end

  local localAim = world.distance(aim, mcontroller.position())
  animator.setFlipped(localAim[1] < 0)
  if mcontroller.onGround() then
    if math.abs(moveDir) > 0 then
      if moveDir * localAim[1] > 0 then
        animator.setAnimationState("body", "move")
      else
        animator.setAnimationState("body", "movebackwards")
      end
    else
      animator.setAnimationState("body", "idle")
    end
  else
    self.jumping = false
    if mcontroller.yVelocity() > 0.0 then
      animator.setAnimationState("body", "jump")
    else
      animator.setAnimationState("body", "fall")
    end
  end

  local driving = moveDir ~= 0
  if driving and not self.driving then
    animator.playSound("engineDrive", -1)
  elseif not driving then
    animator.stopAllSounds("engineDrive", 0.5)
  end
  self.driving = driving
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