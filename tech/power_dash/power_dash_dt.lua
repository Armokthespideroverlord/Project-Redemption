require "/tech/doubletap.lua"

function init()
  self.dashing = false
  self.dashfxtimer = 0
  self.dashfxtime = 10
  self.airDashing = false
  self.dashDirection = 0
  self.dashTimer = 0
  self.dashCooldownTimer = 0
  self.rechargeEffectTimer = 0
  self.timerdelta = 0

  self.dashControlForce = config.getParameter("dashControlForce")
  self.dashSpeed = config.getParameter("dashSpeed")
  self.dashDuration = config.getParameter("dashDuration")
  self.dashCooldown = config.getParameter("dashCooldown")
  self.groundOnly = config.getParameter("groundOnly")
  self.stopAfterDash = config.getParameter("stopAfterDash")
  self.rechargeDirectives = config.getParameter("rechargeDirectives", "?fade=CCCCFFFF=0.25")
  self.rechargeEffectTime = config.getParameter("rechargeEffectTime", 0.1)

  self.doubleTap = DoubleTap:new({"left", "right"}, config.getParameter("maximumDoubleTapTime"), function(dashKey)
      if self.dashTimer == 0
          and self.dashCooldownTimer == 0
          and groundValid()
	  and not status.statPositive("activeMovementAbilities")
          and not mcontroller.crouching() then

        startDash(dashKey == "left" and -1 or 1)
      end
    end)

  animator.setAnimationState("dashing", "off")
end

function uninit()
  status.clearPersistentEffects("movementAbility")
  tech.setParentDirectives()
end

function update(args)
  --[[
  if args.moves["special1"] and (args.moves["left"] or args.moves["right"]) then
	  if self.dashTimer == 0
          and self.dashCooldownTimer == 0
          and groundValid()
          and not mcontroller.crouching() then
	    local direction = 1
	    if args.moves["left"] then direction = -1 end
        startDash(direction)
      end
  end
  ]]--
  
  self.timerdelta = args.dt

	if self.dashing == true then
		self.dashfxtimer = self.dashfxtimer - 1
		if self.dashfxtimer < 1 then
			self.dashing = false
		    animator.setAnimationState("dashing", "off")
		    animator.setParticleEmitterActive("dashParticles", false)
			status.clearPersistentEffects("isn_rktpun_inv")
			tech.setParentDirectives()
		end
	end


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

  if self.dashTimer > 0 then
    status.setPersistentEffects("movementAbility",{{stat="activeMovementAbilities",amount=1}})
    mcontroller.controlApproachVelocity({self.dashSpeed * self.dashDirection, 0}, self.dashControlForce)
    mcontroller.controlMove(self.dashDirection, true)

    if self.airDashing then
      mcontroller.setYVelocity(0)
    end
    mcontroller.controlModifiers({jumpingSuppressed = true})

    animator.setFlipped(mcontroller.facingDirection() == -1)

    self.dashTimer = math.max(0, self.dashTimer - args.dt)

    if self.dashTimer == 0 then
      endDash()
    end
  end
end

function groundValid()
  return mcontroller.groundMovement() or not self.groundOnly
end

function startDash(direction)
  self.dashing = true
  self.dashDirection = direction
  self.dashTimer = self.dashDuration
  self.airDashing = not mcontroller.groundMovement()
  animator.playSound("startDash")
  animator.setAnimationState("dashing", "on")
  self.dashfxtimer = self.dashfxtime
  animator.setParticleEmitterActive("dashParticles", true)
  status.addPersistentEffect("isn_rktpun_inv", {stat = "invulnerable", amount = 1})
  tech.setParentDirectives("")
  local projpower = 10 * status.stat("powerMultiplier")
  world.spawnProjectile("power_dash_prj", mcontroller.position(), entity.id(), {self.dashDirection,0}, true, {power = projpower, timeToLive = math.max(0, self.dashTimer - self.timerdelta), damageTeam = entity.damageTeam()})
end

function endDash()
  status.clearPersistentEffects("movementAbility")
  if self.stopAfterDash then
    local movementParams = mcontroller.baseParameters()
    local currentVelocity = mcontroller.velocity()
    if math.abs(currentVelocity[1]) > movementParams.runSpeed then
      mcontroller.setVelocity({movementParams.runSpeed * self.dashDirection, 0})
    end
    mcontroller.controlApproachXVelocity(self.dashDirection * movementParams.runSpeed, self.dashControlForce)
  end

  self.dashCooldownTimer = self.dashCooldown
  status.addEphemeralEffect("r_power_dash_cooldown")
end
