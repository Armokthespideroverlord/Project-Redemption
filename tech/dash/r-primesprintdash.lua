require "/tech/doubletap.lua"

function init()
  -- Sprint parameters
  self.energyCostPerSecond = config.getParameter("energyCostPerSecond")
  self.dashControlForce = config.getParameter("dashControlForce")
  self.dashSpeedModifier = config.getParameter("dashSpeedModifier")
  self.groundOnly = config.getParameter("groundOnly")
  self.stopAfterDash = config.getParameter("stopAfterDash")

  -- Blinkdash parameters
  self.mode = "none"
  self.blinkTimer = 0
  self.dashCooldownTimer = 0
  self.rechargeEffectTimer = 0
  self.targetPosition = nil

  self.blinkOutTime = config.getParameter("blinkOutTime")
  self.blinkInTime = config.getParameter("blinkInTime")
  self.blinkMaxDistance = config.getParameter("dashDistance")
  self.dashCooldown = config.getParameter("dashCooldown")
  self.rechargeDirectives = config.getParameter("rechargeDirectives", "?fade=CCCCFFFF=0.25")
  self.rechargeEffectTime = config.getParameter("rechargeEffectTime", 0.1)

  self.dashDirection = nil
  self.runHeld = false

  self.doubleTap = DoubleTap:new({"left", "right"}, config.getParameter("maximumDoubleTapTime"), function(dashKey)
      local direction = dashKey == "left" and -1 or 1

      if self.runHeld then
        tryStartSprint(direction)
      else
        tryStartBlink(direction)
      end
    end)
end

function uninit()
  tech.setParentDirectives()
  status.clearPersistentEffects("movementAbility")
  animator.setAnimationState("dashing", "off")
  animator.setParticleEmitterActive("dashParticles", false)
end

function update(args)
  self.runHeld = args.moves["run"]

  if self.dashCooldownTimer > 0 then
    self.dashCooldownTimer = math.max(0, self.dashCooldownTimer - args.dt)
    if self.dashCooldownTimer == 0 then
      self.rechargeEffectTimer = self.rechargeEffectTime
      tech.setParentDirectives(self.rechargeDirectives)
      animator.playSound("recharge")
    end
  end

  if self.rechargeEffectTimer > 0 then
    self.rechargeEffectTimer = math.max(0, self.rechargeEffectTimer - args.dt)
    if self.rechargeEffectTimer == 0 then
      tech.setParentDirectives()
    end
  end

  self.doubleTap:update(args.dt, args.moves)

  if self.mode ~= "none" then
    updateBlink(args)
  elseif self.dashDirection then
    updateSprint(args)
  end
end

function tryStartSprint(direction)
  if self.dashDirection
      or not groundValid()
      or mcontroller.facingDirection() ~= direction
      or mcontroller.crouching()
      or status.resourceLocked("energy")
      or status.statPositive("activeMovementAbilities") then
    return
  end

  startSprint(direction)
end

function tryStartBlink(direction)
  if self.mode ~= "none"
      or self.dashCooldownTimer > 0
      or not groundValid()
      or mcontroller.crouching()
      or status.statPositive("activeMovementAbilities") then
    return
  end

  self.targetPosition = findTargetPosition(direction, self.blinkMaxDistance)
  if self.targetPosition then
    self.mode = "start"
  end
end

function updateSprint(args)
  local moveKey = self.dashDirection > 0 and "right" or "left"
  if args.moves[moveKey]
      and not mcontroller.liquidMovement()
      and not dashBlocked() then

    if mcontroller.facingDirection() == self.dashDirection then
      if status.overConsumeResource("energy", self.energyCostPerSecond * args.dt) then
        mcontroller.controlModifiers({speedModifier = self.dashSpeedModifier})

        animator.setAnimationState("dashing", "on")
        animator.setParticleEmitterActive("dashParticles", true)
      else
        endSprint()
      end
    else
      animator.setAnimationState("dashing", "off")
      animator.setParticleEmitterActive("dashParticles", false)
    end
  else
    endSprint()
  end
end

function updateBlink(args)
  if self.mode == "start" then
    mcontroller.setVelocity({0, 0})
    tech.setToolUsageSuppressed(true)
    self.mode = "out"
    self.blinkTimer = 0
    animator.playSound("activate")
    status.setPersistentEffects("movementAbility", {{stat = "activeMovementAbilities", amount = 1}})
  elseif self.mode == "out" then
    tech.setParentDirectives("?multiply=00000000")
    animator.setAnimationState("blinking", "out")
    mcontroller.setVelocity({0, 0})
    self.blinkTimer = self.blinkTimer + args.dt

    if self.blinkTimer > self.blinkOutTime then
      mcontroller.setPosition(self.targetPosition)
      self.targetPosition = nil
      self.mode = "in"
      self.blinkTimer = 0
    end
  elseif self.mode == "in" then
    tech.setParentDirectives()
    animator.setAnimationState("blinking", "in")
    mcontroller.setVelocity({0, 0})
    self.blinkTimer = self.blinkTimer + args.dt

    if self.blinkTimer > self.blinkInTime then
      tech.setToolUsageSuppressed(false)
      self.mode = "none"
      self.dashCooldownTimer = self.dashCooldown
      status.clearPersistentEffects("movementAbility")
    end
  end
end

function groundValid()
  return mcontroller.groundMovement() or not self.groundOnly
end

function dashBlocked()
  return mcontroller.velocity()[1] == 0
end

function startSprint(direction)
  self.dashDirection = direction
  status.setPersistentEffects("movementAbility", {{stat = "activeMovementAbilities", amount = 1}})
  animator.setFlipped(self.dashDirection == -1)
  animator.setAnimationState("dashing", "on")
  animator.setParticleEmitterActive("dashParticles", true)
end

function endSprint()
  status.clearPersistentEffects("movementAbility")

  if self.stopAfterDash then
    local movementParams = mcontroller.baseParameters()
    local currentVelocity = mcontroller.velocity()
    if math.abs(currentVelocity[1]) > movementParams.runSpeed then
      mcontroller.setVelocity({movementParams.runSpeed * self.dashDirection, 0})
    end
    mcontroller.controlApproachXVelocity(self.dashDirection * movementParams.runSpeed, self.dashControlForce)
  end

  animator.setAnimationState("dashing", "off")
  animator.setParticleEmitterActive("dashParticles", false)

  self.dashDirection = nil
end

function findTargetPosition(dir, maxDist)
  local dist = 1
  local targetPosition
  local collisionPoly = mcontroller.collisionPoly()
  local testPos = mcontroller.position()

  while dist <= maxDist do
    testPos[1] = testPos[1] + dir
    if not world.polyCollision(collisionPoly, testPos, {"Null", "Block", "Dynamic", "Slippery"}) then
      local oneDown = {testPos[1], testPos[2] - 1}
      if not world.polyCollision(collisionPoly, oneDown, {"Null", "Block", "Dynamic", "Platform"}) then
        testPos = oneDown
      end
    else
      local oneUp = {testPos[1], testPos[2] + 1}
      if not world.polyCollision(collisionPoly, oneUp, {"Null", "Block", "Dynamic", "Slippery"}) then
        testPos = oneUp
      else
        break
      end
    end
    targetPosition = {testPos[1], testPos[2]}
    dist = dist + 1
  end

  if targetPosition then
    local towardGround = {targetPosition[1], targetPosition[2] - 0.8}
    local groundPosition = world.resolvePolyCollision(collisionPoly, towardGround, 0.8, {"Null", "Block", "Dynamic", "Platform"})
    if groundPosition and not (groundPosition[1] == towardGround[1] and groundPosition[2] == towardGround[2]) then
      targetPosition = groundPosition
    end
  end

  return targetPosition
end