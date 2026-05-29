function init()
  self.holdingJump = false
  self.active = false
end

function input(args)
  if args.moves["jump"] and mcontroller.jumping() then
    self.holdingJump = true
  elseif not args.moves["jump"] then
    self.holdingJump = false
  end

  if args.moves["jump"] and not mcontroller.canJump() and not self.holdingJump then
    return "jetpack"
  else
    return nil
  end
end

function update(args)
  local action = input(args)
  local jetpackSpeed = config.getParameter("jetpackSpeed")
  local jetpackControlForce = config.getParameter("jetpackControlForce")
  local energyUsagePerSecond = config.getParameter("energyUsagePerSecond")

  if action == "jetpack" and status.consumeResource("energy", energyUsagePerSecond * args.dt) then
    animator.setAnimationState("jetpack", "on")
    mcontroller.controlApproachYVelocity(jetpackSpeed, jetpackControlForce)

    if not self.active then
      animator.playSound("activate")
    end
    self.active = true
  else
    self.active = false
    animator.setAnimationState("jetpack", "off")
  end
end