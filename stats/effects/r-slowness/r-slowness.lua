function init()
  effect.addStatModifierGroup({
    {stat = "jumpModifier", amount = -0.50}
  })
end

function update(dt)
  mcontroller.controlModifiers({
      groundMovementModifier = 0.5,
      speedModifier = 0.5,
      airJumpModifier = 0.5
    })
end

function uninit()

end
