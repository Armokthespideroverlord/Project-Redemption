require "/tech/distortionsphere/distortionsphere.lua"
require "/scripts/util.lua"
require "/scripts/rect.lua"
require "/scripts/poly.lua"
require "/scripts/status.lua"

function init()
  initCommonParameters()

  self.ballLiquidSpeed = config.getParameter("ballLiquidSpeed")

  self.chargePitchAdjust = config.getParameter("chargePitchAdjust")
  self.chargeEnergy = config.getParameter("chargeEnergy")
  self.chargeTime = config.getParameter("chargeTime")
  self.launchVelocity = config.getParameter("launchVelocity")
  self.chargeEnergyPerSecond = self.chargeEnergy / self.chargeTime[2]

  self.boostMovementParameters = util.mergeTable(copy(self.transformedMovementParameters), config.getParameter("boostMovementParameters"))
  self.boostTime = config.getParameter("boostTime")

  self.chargeTimer = 0
  self.boostTimer = 0
  self.chargeSoundPlaying = false

  self.ignorePlatforms = config.getParameter("ignorePlatforms")
  self.damageDisableTime = config.getParameter("damageDisableTime")
  self.damageDisableTimer = 0

  self.gripReapplyDelay = config.getParameter("gripReapplyDelay", 3.0)
  self.gripDisableTimer = 0

  self.headingAngle = nil

  self.normalCollisionSet = {"Block", "Dynamic"}
  if self.ignorePlatforms then
    self.platformCollisionSet = self.normalCollisionSet
  else
    self.platformCollisionSet = {"Block", "Dynamic", "Platform"}
  end

  self.damageListener = damageListener("damageTaken", function(notifications)
    for _, notification in pairs(notifications) do
      if notification.healthLost > 0 and notification.sourceEntityId ~= entity.id() then
        damaged()
        return
      end
    end
  end)
end

function uninit()
  animator.setParticleEmitterActive("chargeLeft", false)
  animator.setParticleEmitterActive("chargeRight", false)
  animator.stopAllSounds("chargeLoop")
  storePosition()
  deactivate()
end

function update(args)
  restoreStoredPosition()

  if not self.specialLast and args.moves["special1"] then
    attemptActivation()
    if self.active and not self.forceTimer then
      self.chargeDirection = mcontroller.facingDirection()
      self.chargeTimer = 0
    end
  end
  self.specialLast = args.moves["special1"]

  if not args.moves["special1"] then
    self.forceTimer = nil
  end

  self.damageDisableTimer = math.max(0, self.damageDisableTimer - args.dt)
  self.gripDisableTimer = math.max(0, self.gripDisableTimer - args.dt)
  self.damageListener:update()

  if self.active then
    self.boostTimer = math.max(0, self.boostTimer - args.dt)

    local inLiquid = mcontroller.liquidPercentage() > 0.2

    if self.chargeDirection then
      self.headingAngle = nil
      self.transformedMovementParameters.gravityEnabled = true
      mcontroller.controlParameters(self.transformedMovementParameters)

      if self.specialLast and not mcontroller.groundMovement() then
        stopChargeEffects()
      elseif self.specialLast and (self.chargeTimer == self.chargeTime[2] or status.overConsumeResource("energy", self.chargeEnergyPerSecond * args.dt)) then
        self.chargeTimer = math.min(self.chargeTimer + args.dt, self.chargeTime[2])
        self.angularVelocity = -self.chargeDirection * self.launchVelocity[1] * chargeRatio()
        mcontroller.controlModifiers({movementSuppressed = true, facingSuppressed = true})
        mcontroller.controlApproachXVelocity(0, 1000)
        startChargeEffects()
        animator.setSoundPitch("chargeLoop", 1.0 + chargeRatio(), 0)
      else
        if self.chargeTimer >= self.chargeTime[1] then
          local launchVelocity = vec2.mul({self.launchVelocity[1] * self.chargeDirection, self.launchVelocity[2]}, chargeRatio())
          mcontroller.setVelocity(launchVelocity)
          animator.playSound("launch")
          self.boostTimer = self.boostTime
          self.gripDisableTimer = self.gripReapplyDelay
        else
          self.angularVelocity = 0
        end
        stopChargeEffects()
        animator.setSoundPitch("chargeLoop", 1.0, 0)
        self.chargeDirection = nil
      end
    else
      local groundDirection
      local moveX = 0
      if args.moves["right"] then moveX = moveX + 1 end
      if args.moves["left"] then moveX = moveX - 1 end

      if self.damageDisableTimer == 0 and self.gripDisableTimer == 0 then
        groundDirection = findGroundDirection()
      end

      if groundDirection then
        if not self.headingAngle then
          self.headingAngle = (math.atan(groundDirection[2], groundDirection[1]) + math.pi / 2) % (math.pi * 2)
        end

        local moveX = 0
        if args.moves["right"] then moveX = moveX + 1 end
        if args.moves["left"] then moveX = moveX - 1 end

        if moveX ~= 0 then
          local adjustment = 0
          for a = 0, math.pi, math.pi / 4 do
            local testPos = vec2.add(mcontroller.position(), vec2.rotate({moveX * 0.25, 0}, self.headingAngle + (moveX * a)))
            adjustment = moveX * a
            if not world.polyCollision(poly.translate(poly.scale(mcontroller.collisionPoly(), 1.0), testPos), nil, self.normalCollisionSet) then
              break
            end
          end
          self.headingAngle = self.headingAngle + adjustment

          adjustment = 0
          for a = 0, -math.pi, -math.pi / 4 do
            local testPos = vec2.add(mcontroller.position(), vec2.rotate({moveX * 0.25, 0}, self.headingAngle + (moveX * a)))
            if world.polyCollision(poly.translate(poly.scale(mcontroller.collisionPoly(), 1.0), testPos), nil, self.normalCollisionSet) then
              break
            end
            adjustment = moveX * a
          end
          self.headingAngle = self.headingAngle + adjustment

          local groundAngle = self.headingAngle - (math.pi / 2)
          mcontroller.controlApproachVelocity(vec2.withAngle(groundAngle, self.ballSpeed), 300)

          local moveDirection = vec2.rotate({moveX, 0}, self.headingAngle)
          mcontroller.controlApproachVelocityAlongAngle(math.atan(moveDirection[2], moveDirection[1]), self.ballSpeed, 2000)

          -- Use world-space X component of the move direction so the spin
          -- matches movement regardless of surface orientation.
          self.angularVelocity = -moveDirection[1] * self.ballSpeed
        else
          mcontroller.controlApproachVelocity({0, 0}, 2000)
          self.angularVelocity = 0
        end

        mcontroller.controlDown()
        updateAngularVelocity(args.dt, inLiquid, moveX)
        self.transformedMovementParameters.gravityEnabled = false
      else
        updateAngularVelocity(args.dt, inLiquid, moveX)
        self.transformedMovementParameters.gravityEnabled = true
      end

      if self.boostTimer > 0 then
        mcontroller.controlParameters(self.boostMovementParameters)
      else
        if inLiquid then
          self.transformedMovementParameters.runSpeed = self.ballLiquidSpeed
          self.transformedMovementParameters.walkSpeed = self.ballLiquidSpeed
        else
          self.transformedMovementParameters.runSpeed = self.ballSpeed
          self.transformedMovementParameters.walkSpeed = self.ballSpeed
        end
        mcontroller.controlParameters(self.transformedMovementParameters)
      end
    end

    status.setResourcePercentage("energyRegenBlock", 1.0)
    updateRotationFrame(args.dt)
    checkForceDeactivate(args.dt)
  else
    self.headingAngle = nil
  end

  updateTransformFade(args.dt)
  self.lastPosition = mcontroller.position()
end

function updateAngularVelocity(dt, inLiquid, controlDirection)
  if mcontroller.isColliding() or mcontroller.groundMovement() then
    local positionDiff = world.distance(self.lastPosition or mcontroller.position(), mcontroller.position())
    local speed = vec2.mag(positionDiff) / math.max(dt, 1e-6) / self.ballRadius

    if self.headingAngle then
      local tangent = vec2.withAngle(self.headingAngle, 1.0)
      local dot = positionDiff[1] * tangent[1] + positionDiff[2] * tangent[2]
      local sign = 0
      if dot > 0 then sign = 1 elseif dot < 0 then sign = -1 end
      self.angularVelocity = sign * speed
    else
      self.angularVelocity = -speed
      if positionDiff[1] > 0 then
        self.angularVelocity = -self.angularVelocity
      end
    end
  elseif inLiquid then
    if controlDirection and controlDirection ~= 0 then
      self.angularVelocity = 1.5 * self.ballLiquidSpeed * controlDirection
    else
      self.angularVelocity = self.angularVelocity - (self.angularVelocity * 0.8 * dt)
      if math.abs(self.angularVelocity) < 0.1 then
        self.angularVelocity = 0
      end
    end
  end
end

function chargeRatio()
  return self.chargeTimer / self.chargeTime[2]
end

function startChargeEffects()
  if not self.chargeSoundPlaying then
    animator.playSound("chargeLoop", -1)
    self.chargeSoundPlaying = true
  end
  if self.chargeTimer >= self.chargeTime[1] then
    animator.setParticleEmitterActive("charge" .. (self.chargeDirection < 0 and "Left" or "Right"), true)
  end
end

function stopChargeEffects()
  if self.chargeSoundPlaying then
    animator.stopAllSounds("chargeLoop")
    self.chargeSoundPlaying = false
  end
  animator.setParticleEmitterActive("chargeLeft", false)
  animator.setParticleEmitterActive("chargeRight", false)
end

function damaged()
  if self.active then
    self.damageDisableTimer = self.damageDisableTime
  end
end

function findGroundDirection()
  for i = 0, 3 do
    local angle = (i * math.pi / 2) - math.pi / 2
    local collisionSet = i == 1 and self.platformCollisionSet or self.normalCollisionSet
    local testPos = vec2.add(mcontroller.position(), vec2.withAngle(angle, 0.25))
    if world.polyCollision(poly.translate(mcontroller.collisionPoly(), testPos), nil, collisionSet) then
      return vec2.withAngle(angle, 1.0)
    end
  end
end