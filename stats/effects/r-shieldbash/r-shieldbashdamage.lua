function init()
status.applySelfDamageRequest({
       -- damageType = "IgnoresDef",
        damage = effect.duration(),
        damageSourceKind = "impact",
        sourceEntityId = entity.id()
      })
  effect.expire()
end