require "/scripts/vec2.lua"
require "/scripts/rect.lua"
require "/scripts/poly.lua"
require "/scripts/status.lua"

function init()
  initCommonParameters()
  animator.setParticleEmitterActive("spinning", false)
  animator.setParticleEmitterActive("charge", false)
end

function initCommonParameters()
  self.angularVelocity = 0
  self.angle = 0
  self.transformFadeTimer = 0
  self.chargingTimer = 0
  self.flyTime = 0
  self.aimMagnitude = 0
  
  self.animatorFlying = false
  self.flyShouldActive = true

  self.headingAngle = nil
  self.forceTimer = nil

  self.energyCost = config.getParameter("energyCost")
  self.ballRadius = config.getParameter("ballRadius")
  self.ballFrames = config.getParameter("ballFrames")
  self.ballSpeed = config.getParameter("ballSpeed")
  self.shiftBallSpeed = config.getParameter("shiftBallSpeed")
  self.transformFadeTime = config.getParameter("transformFadeTime", 0.3)
  self.transformedMovementParameters = config.getParameter("transformedMovementParameters")
  self.transformedMovementParameters.runSpeed = self.ballSpeed
  self.transformedMovementParameters.walkSpeed = self.shiftBallSpeed
  self.basePoly = mcontroller.baseParameters().standingPoly

  self.chargingTime = config.getParameter("chargingTime")
  self.maxFlyTime = config.getParameter("maxFlyTime")
  self.leastFlyTime = config.getParameter("leastFlyTime")
  self.chargingStoppingForce = config.getParameter("chargingStoppingForce", 200)
  self.flyVelocity = config.getParameter("flyVelocity")
  self.flyVelocitySlow = config.getParameter("flyVelocitySlow")
  self.cancelDistance = config.getParameter("cancelDistance")
  self.chargeEnergyPerSecond = config.getParameter("chargeEnergyPerSecond")
  self.launchEnergy = config.getParameter("launchEnergy")

  self.shielded = config.getParameter("shielded", false)

  self.collisionSet = {"Null", "Block", "Dynamic", "Slippery"}
  self.ignorePlatforms = config.getParameter("ignorePlatforms")

  self.normalCollisionSet = {"Block", "Dynamic"}
  self.platformCollisionSet = self.ignorePlatforms and self.normalCollisionSet or {"Block", "Dynamic", "Platform"}

  self.forceDeactivateTime = config.getParameter("forceDeactivateTime", 3.0)
  self.forceShakeMagnitude = config.getParameter("forceShakeMagnitude", 0.125)

  -- Projectile attack while flying after charged launch
  self.flyAttackProjectile = config.getParameter("flyAttackProjectile")
  self.flyAttackProjectileConfig = config.getParameter("flyAttackProjectileConfig", {})
  self.flyAttackProjectilePower = config.getParameter("flyAttackProjectilePower", 0)
  self.flyAttackInterval = config.getParameter("flyAttackInterval", 0.2)
  self.flyAttackTimer = 0
  self.flyAttackActive = false
end

function uninit()
  self.charging = false
  self.shouldFly = false
  self.animatorFlying = false
  self.forceTimer = nil
  mcontroller.setVelocity({0,0})
  animator.stopAllSounds("chargeLoop")
  animator.stopAllSounds("forceDeactivate")
  storePosition()
  deactivate()
end

function update(args)
  restoreStoredPosition()

  if not self.specialLast and args.moves["special1"] then
    attemptActivation()
  end
  self.specialLast = args.moves["special1"]

  if not args.moves["special1"] then
    self.forceTimer = nil
  end

  if self.active then
    if not self.charging and self.shouldFly == false then
      self.transformedMovementParameters.gravityEnabled = true
    end

    mcontroller.controlParameters(self.transformedMovementParameters)
    status.setResourcePercentage("energyRegenBlock", 1.0)

    if self.forceTimer then
      checkForceDeactivate(args.dt)
    else
      local wantsCharge = args.moves["primaryFire"] and self.flyShouldActive == true
      if wantsCharge and status.overConsumeResource("energy", self.chargeEnergyPerSecond * args.dt) then
        if not self.charging then
          self.flyAttackTimer = 0
          self.flyAttackActive = true
        end
        self.charging = true
        self.shouldFly = false
        self.flyTime = 0
        self.aimMagnitude = vec2.mag(vec2.sub(mcontroller.position(), tech.aimPosition()))
        self.flyingDir = vec2.norm(vec2.sub(tech.aimPosition(), mcontroller.position()))
      else
        self.charging = false
        if not self.shouldFly then
          self.flyAttackActive = false
        end
        if checkFlyAngle() then
          self.chargingTimer = 0
        end
      end

      if not self.charging then
        stopChargeEffects()
        if self.chargingTimer >= self.chargingTime and self.aimMagnitude >= self.cancelDistance then
          self.shouldFly = true
          self.animatorFlying = true
          status.overConsumeResource("energy", self.launchEnergy)
          -- mark that this launch should spawn damaging projectiles while flying
          self.flyAttackActive = true
          self.flyAttackTimer = 0
        end
        self.chargingTimer = 0

        if self.shouldFly == true then
          mcontroller.controlDown()
          if self.flyTime == 0 then animator.playSound("boost") end
          self.flyTime = math.min((self.flyTime + args.dt), self.maxFlyTime)   
          if self.flyTime < self.maxFlyTime and not status.statPositive("mwhaddon_techDisable") then
            self.transformedMovementParameters.gravityEnabled = false
            mcontroller.setVelocity(vec2.mul(self.flyingDir, self.flyVelocity))
            if self.flyTime >= self.leastFlyTime then
              updateClimb(args)
              self.flyShouldActive = true
            else
              self.animatorFlying = false
              self.flyShouldActive = false
            end
            if self.flyAttackActive then
              updateFlyAttackProjectile(args.dt)
            end
          else
            self.animatorFlying = false
            self.shouldFly = false
            self.flyAttackActive = false
          end
        else
          animator.setParticleEmitterActive("spinning", false)
          updateClimb(args)
        end
      else
        if args.moves["run"] then
          self.flyVelocity = config.getParameter("flyVelocity")
        else
          self.flyVelocity = self.flyVelocitySlow
        end

        startChargeEffects()
        animator.setSoundPitch("chargeLoop", 1 + chargeRatio(), 0)
        self.chargingTimer = math.min((self.chargingTimer + args.dt), self.chargingTime)
        self.transformedMovementParameters.gravityEnabled = false
        self.angularVelocity = 0
        if not mcontroller.onGround() then
          mcontroller.controlApproachVelocity({0,0}, self.chargingStoppingForce)
        end
        if self.flyAttackActive then
          updateFlyAttackProjectile(args.dt)
        end
      end

      updateAngularVelocity(args.dt)
      updateRotationFrame(args.dt)
    end
  else
    self.headingAngle = nil
  end

  updateTagAndDirectives(args.dt)

  self.lastPosition = mcontroller.position()
end

function updateClimb(args)
  local groundDirection = findGroundDirection()
  if groundDirection then
    if self.shouldFly == true then
      self.flyTime = self.maxFlyTime
      self.shouldFly = false
      self.animatorFlying = false
      self.flyAttackActive = false
      animator.playSound("wallCrash")
    end

    if not self.headingAngle then
      self.headingAngle = (math.atan(groundDirection[2], groundDirection[1]) + math.pi / 2) % (math.pi * 2)
    end

    local moveX = 0
    if args.moves["right"] then moveX = moveX + 1 end
    if args.moves["left"] then moveX = moveX - 1 end
    if moveX ~= 0 then
      local adjustment = 0
      for a = 0, math.pi, math.pi / 4 do
        local testPos = vec2.add(mcontroller.position(), vec2.rotate({moveX * 0.3, 0}, self.headingAngle + (moveX * a)))
        adjustment = moveX * a
        if not world.polyCollision(poly.translate(poly.scale(mcontroller.collisionPoly(), 1.0), testPos), nil, self.normalCollisionSet) then
          break
        end
      end
      self.headingAngle = self.headingAngle + adjustment

      adjustment = 0
      for a = 0, -math.pi, -math.pi / 4 do
        local testPos = vec2.add(mcontroller.position(), vec2.rotate({moveX * 0.3, 0}, self.headingAngle + (moveX * a)))
        if world.polyCollision(poly.translate(poly.scale(mcontroller.collisionPoly(), 1.0), testPos), nil, self.normalCollisionSet) then
          break
        end
        adjustment = moveX * a
      end
      self.headingAngle = self.headingAngle + adjustment

      local speed = args.moves["run"] and self.ballSpeed or self.shiftBallSpeed
      local groundAngle = self.headingAngle - (math.pi / 2)
      mcontroller.controlApproachVelocity(vec2.withAngle(groundAngle, speed), 1200)

      local moveDirection = vec2.rotate({moveX, 0}, self.headingAngle)
      mcontroller.controlApproachVelocityAlongAngle(math.atan(moveDirection[2], moveDirection[1]), speed, 8000)

      self.angularVelocity = -moveX * speed
    else
      mcontroller.controlApproachVelocity({0,0}, 4000)
      self.angularVelocity = 0
    end

    mcontroller.controlDown()

    self.transformedMovementParameters.gravityEnabled = false
  else
    if self.shouldFly == false then
      self.transformedMovementParameters.gravityEnabled = true
    end
  end
end

function checkFlyAngle()
  if self.flyingDir then
    local testPos = vec2.add(mcontroller.position(), vec2.mul(self.flyingDir, 4.5))
    return world.lineTileCollision(mcontroller.position(), testPos)
  else
    return false
  end
end

function attemptActivation()
  if not self.active
      and not tech.parentLounging()
      and not status.statPositive("activeMovementAbilities")
      and status.overConsumeResource("energy", self.energyCost) then
        
    self.transformedMovementParameters.gravityEnabled = true
    local pos = transformPosition()
    if pos then
      mcontroller.setPosition(pos)
      activate()
    end
  elseif self.active then
    local pos = restorePosition()
    if pos then
      mcontroller.setPosition(pos)
      deactivate()
    elseif not self.forceTimer then
      animator.playSound("forceDeactivate", -1)
      self.forceTimer = 0
    end
  end
end

function checkForceDeactivate(dt)
  animator.resetTransformationGroup("ball")

  if self.forceTimer then
    self.forceTimer = self.forceTimer + dt
    mcontroller.controlModifiers({
      movementSuppressed = true
    })

    local shake = vec2.mul(vec2.withAngle((math.random() * math.pi * 2), self.forceShakeMagnitude), self.forceTimer / self.forceDeactivateTime)
    animator.translateTransformationGroup("ball", shake)
    if self.forceTimer >= self.forceDeactivateTime then
      deactivate()
      self.forceTimer = nil
    else
      attemptActivation()
    end
    return true
  else
    animator.stopAllSounds("forceDeactivate")
    return false
  end
end

function storePosition()
  if self.active then
    storage.restorePosition = restorePosition()

    if storage.restorePosition then
      storage.lastActivePosition = mcontroller.position()
      mcontroller.setPosition(storage.restorePosition)
    end
  end
end

function restoreStoredPosition()
  if storage.restorePosition then
    if vec2.mag(vec2.sub(mcontroller.position(), storage.lastActivePosition)) < 1 then
      mcontroller.setPosition(storage.restorePosition)
    end
    storage.lastActivePosition = nil
    storage.restorePosition = nil
  end
end

function updateAngularVelocity(dt)
  if self.shouldFly == true then
    self.angularVelocity = self.flyVelocity * 0.7
  elseif self.charging then
    self.angularVelocity = self.flyVelocity * chargeRatio() * 0.7
  end
  if mcontroller.groundMovement() then
    local positionDiff = world.distance(self.lastPosition or mcontroller.position(), mcontroller.position())
    self.angularVelocity = -vec2.mag(positionDiff) / dt / self.ballRadius

    if positionDiff[1] > 0 then
      self.angularVelocity = -self.angularVelocity
    end
  end
end

function updateRotationFrame(dt)
  self.angle = math.fmod(math.pi * 2 + self.angle + self.angularVelocity * dt, math.pi * 2)

  local rotationFrame = math.floor(self.angle / math.pi * self.ballFrames) % self.ballFrames
  animator.setGlobalTag("rotationFrame", rotationFrame)
end

function updateTagAndDirectives(dt)
  if self.transformFadeTimer > 0 then
    self.transformFadeTimer = math.max(0, self.transformFadeTimer - dt)
    animator.setGlobalTag("ballDirectives", string.format("?fade=FFFFFFFF;%.1f", math.min(1.0, self.transformFadeTimer / (self.transformFadeTime - 0.15))))
  elseif self.transformFadeTimer < 0 then
    self.transformFadeTimer = math.min(0, self.transformFadeTimer + dt)
    tech.setParentDirectives(string.format("?fade=FFFFFFFF;%.1f", math.min(1.0, -self.transformFadeTimer / (self.transformFadeTime - 0.15))))
  else
    if self.charging and self.aimMagnitude < self.cancelDistance then
      animator.setGlobalTag("disabledTag", "Disabled")
    else
      animator.setGlobalTag("disabledTag", "")
    end
    if self.shouldFly == true or self.animatorFlying == true then
      animator.setGlobalTag("ballDirectives", "?border=1;008cd9;00000000")
    elseif self.charging then
      local num = math.floor(chargeRatio() * 255)
      animator.setGlobalTag("ballDirectives", string.format("?border=1;008cd9%02X;00000000",num))
    else
      animator.setGlobalTag("ballDirectives", "")
    end
    tech.setParentDirectives()
  end
end

function positionOffset()
  return minY(self.transformedMovementParameters.collisionPoly) - minY(self.basePoly)
end

function transformPosition(pos)
  pos = pos or mcontroller.position()
  local groundPos = world.resolvePolyCollision(self.transformedMovementParameters.collisionPoly, {pos[1], pos[2] - positionOffset()}, 1, self.collisionSet)
  if groundPos then
    return groundPos
  else
    return world.resolvePolyCollision(self.transformedMovementParameters.collisionPoly, pos, 1, self.collisionSet)
  end
end

function restorePosition(pos)
  pos = pos or mcontroller.position()
  local groundPos = world.resolvePolyCollision(self.basePoly, {pos[1], pos[2] + positionOffset()}, 1, self.collisionSet)
  if groundPos then
    return groundPos
  else
    return world.resolvePolyCollision(self.basePoly, pos, 1, self.collisionSet)
  end
end

function activate()
  if not self.active then
    animator.burstParticleEmitter("activateParticles")
    animator.playSound("activate")
    animator.setAnimationState("ballState", "activate")
    self.angularVelocity = 0
    self.angle = 0
    self.shouldFly = false
    self.flyTime = 0
    self.transformFadeTimer = self.transformFadeTime
  end
  tech.setParentHidden(true)
  tech.setParentOffset({0, positionOffset()})
  tech.setToolUsageSuppressed(true)
  status.setPersistentEffects("movementAbility", {{stat = "activeMovementAbilities", amount = 1}})
  self.flyShouldActive = true
  self.active = true
  self.animatorFlying = false
  self.transformedMovementParameters.gravityEnabled = true
  self.flyAttackActive = false
end

function deactivate()
  if self.active then
    animator.burstParticleEmitter("deactivateParticles")
    animator.playSound("deactivate")
    animator.setAnimationState("ballState", "deactivate")
    animator.setParticleEmitterActive("spinning", false)
    animator.setParticleEmitterActive("charge", false)
    self.transformFadeTimer = -self.transformFadeTime
  else
    animator.setAnimationState("ballState", "off")
  end
  animator.stopAllSounds("forceDeactivate")
  animator.setGlobalTag("ballDirectives", "")
  animator.setGlobalTag("disabledTag", "")
  tech.setParentHidden(false)
  tech.setParentOffset({0, 0})
  tech.setToolUsageSuppressed(false)
  status.clearPersistentEffects("movementAbility")
  self.angle = 0
  self.active = false
  self.animatorFlying = false
  self.forceTimer = nil

  stopChargeEffects()
  self.flyAttackActive = false
end

function findGroundDirection()
  if status.statPositive("mwhaddon_techDisable") then return nil end
  for i = 0, 3 do
    local angle = (i * math.pi / 2) - math.pi / 2
    local collisionSet = i == 1 and self.platformCollisionSet or self.normalCollisionSet
    local testPos = vec2.add(mcontroller.position(), vec2.withAngle(angle, 0.3))
    if world.polyCollision(poly.translate(mcontroller.collisionPoly(), testPos), nil, collisionSet) then
      return vec2.withAngle(angle, 1.0)
    end
  end
end

function startChargeEffects()
  if not self.chargeSoundPlaying then
    animator.playSound("chargeLoop", -1)
    self.chargeSoundPlaying = true
  end
  if self.chargingTimer >= self.chargingTime then
    animator.setParticleEmitterActive("spinning", true)
    if world.lineTileCollision(mcontroller.position(), vec2.add(mcontroller.position(), {0,-1.3})) then
      animator.setParticleEmitterActive("charge", true)
    end
  end
end

function stopChargeEffects()
  if self.chargeSoundPlaying then
    animator.stopAllSounds("chargeLoop")
    self.chargeSoundPlaying = false
  end
  animator.setParticleEmitterActive("charge", false)
end

function chargeRatio()
  return self.chargingTimer / self.chargingTime
end

function minY(poly)
  local lowest = 0
  for _,point in pairs(poly) do
    if point[2] < lowest then
      lowest = point[2]
    end
  end
  return lowest
end

-- Spawn an attached projectile periodically while flying after a charged launch
function updateFlyAttackProjectile(dt)
  if not self.flyAttackActive or not self.flyAttackProjectile then
    return
  end

  self.flyAttackTimer = self.flyAttackTimer + dt
  if self.flyAttackTimer < self.flyAttackInterval then
    return
  end

  self.flyAttackTimer = self.flyAttackTimer - self.flyAttackInterval

  -- ensure power is passed through if provided separately
  if self.flyAttackProjectilePower > 0 and self.flyAttackProjectileConfig.power == nil then
    self.flyAttackProjectileConfig.power = self.flyAttackProjectilePower
  end

  -- force zero velocity so the projectile stays attached to the sphere
  self.flyAttackProjectileConfig.speed = 0

  world.spawnProjectile(
    self.flyAttackProjectile,
    mcontroller.position(),
    entity.id(),
    {0,0},
    true,
    self.flyAttackProjectileConfig
  )
end


