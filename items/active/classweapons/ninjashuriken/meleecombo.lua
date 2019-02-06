require "/items/active/weapons/melee/meleeweapon.lua"
-- Melee primary ability
MeleeCombo = WeaponAbility:new()

function MeleeCombo:init()
  self.comboStep = 1

  self.energyUsage = self.energyUsage or 0
  self.damageGivenUpdate = 5
  self.hitTimer = 0
  self.aetherPowerMultiplier = config.getParameter("aetherPowerMultiplier", false)

  if self.aetherPowerMultiplier then self.damageConfig.damageSourceKind = "bloodaetherbleeddaggertanto" .. activeItem.hand() end

  self:computeDamageAndCooldowns()

  self.weapon:setStance(self.stances.idle)

  self.edgeTriggerTimer = 0
  self.flashTimer = 0
  self.cooldownTimer = self.cooldowns[1]

  self.animKeyPrefix = self.animKeyPrefix or ""

  self.projectileType = config.getParameter("primaryAbility.projectileType", "ivrpgaetherkunai")
  self.projectileEnergyCost = config.getParameter("primaryAbility.projectileEnergyCost", 0)
  self.projectileParams = config.getParameter("primaryAbility.projectileParameters", {})

  self.weapon.onLeaveAbility = function()
    self.weapon:setStance(self.stances.idle)
  end
end

-- Ticks on every update regardless if this is the active ability
function MeleeCombo:update(dt, fireMode, shiftHeld)
  WeaponAbility.update(self, dt, fireMode, shiftHeld)
  if self.weapon.cooldownTimer and self.weapon.cooldownTimer > 0 then
    self.cooldownTimer = self.weapon.cooldownTimer
    self.weapon.cooldownTimer = 0
  end

  if self.aetherPowerMultiplier then
    self:updateDamageGiven(dt)
  end

  if self.cooldownTimer > 0 then
    self.cooldownTimer = math.max(0, self.cooldownTimer - self.dt)
    if self.cooldownTimer == 0 then
      self:readyFlash()
    end
  end

  if self.flashTimer > 0 then
    self.flashTimer = math.max(0, self.flashTimer - self.dt)
    if self.flashTimer == 0 then
      animator.setGlobalTag("bladeDirectives", "")
    end
  end

  local statusName = "ivrpgwaether" .. activeItem.hand()
  if self.hitTimer > 0 then
    status.setPersistentEffects(statusName, {
      {stat = "powerMultiplier", baseMultiplier = 1 + math.min(self.hitTimer / 30, 1)},
    })
    self.hitTimer = math.max(0, self.hitTimer - dt)
  else
    status.clearPersistentEffects(statusName)
  end

  self.edgeTriggerTimer = math.max(0, self.edgeTriggerTimer - dt)
  if self.lastFireMode ~= (self.activatingFireMode or self.abilitySlot) and fireMode == (self.activatingFireMode or self.abilitySlot) then
    self.edgeTriggerTimer = self.edgeTriggerGrace
  end
  self.lastFireMode = fireMode

  if not self.weapon.currentAbility and self:shouldActivate() then
    self:setState(self.windup)
  end
end

function MeleeCombo:updateDamageGiven(dt)
  local notifications = nil
  notifications, self.damageGivenUpdate = status.inflictedDamageSince(self.damageGivenUpdate)
  if notifications then
    for _,notification in pairs(notifications) do
      if self.damageConfig.damageSourceKind == notification.damageSourceKind then
        if notification.healthLost > 0 then
          self.hitTimer = math.min(self.hitTimer + 1, 30)
          if notification.damageDealt > notification.healthLost and status.statPositive("ivrpgucvampirescaress") then
            status.addEphemeralEffect("regeneration4", 2, activeItem.ownerEntityId())
          end
        end
      end
    end
  end
end

-- State: windup
function MeleeCombo:windup()
  local stance = self.stances["windup"..self.comboStep]

  self.weapon:setStance(stance)

  self.edgeTriggerTimer = 0

  if stance.hold then
    while self.fireMode == (self.activatingFireMode or self.abilitySlot) do
      coroutine.yield()
    end
  else
    util.wait(stance.duration)
  end

  if self.energyUsage then
    status.overConsumeResource("energy", self.energyUsage)
  end

  if self.stances["preslash"..self.comboStep] then
    self:setState(self.preslash)
  else
    self:setState(self.fire)
  end
end

-- State: wait
-- waiting for next combo input
function MeleeCombo:wait()
  local stance = self.stances["wait"..(self.comboStep - 1)]

  self.weapon:setStance(stance)

  util.wait(stance.duration, function()
    if self:shouldActivate() then
      self:setState(self.windup)
      return
    end
  end)

  self.cooldownTimer = math.max(0, self.cooldowns[self.comboStep - 1] - stance.duration)
  self.comboStep = 1
end

-- State: preslash
-- brief frame in between windup and fire
function MeleeCombo:preslash()
  local stance = self.stances["preslash"..self.comboStep]

  self.weapon:setStance(stance)
  self.weapon:updateAim()

  util.wait(stance.duration)

  self:setState(self.fire)
end

-- State: fire
function MeleeCombo:fire()
  local stance = self.stances["fire"..self.comboStep]

  self.weapon:setStance(stance)
  self.weapon:updateAim()

  local animStateKey = self.animKeyPrefix .. (self.comboStep > 1 and "fire"..self.comboStep or "fire")
  animator.setAnimationState("swoosh", animStateKey)
  animator.playSound(animStateKey)

  local swooshKey = self.animKeyPrefix .. (self.elementalType or self.weapon.elementalType) .. "swoosh"
  animator.setParticleEmitterOffsetRegion(swooshKey, self.swooshOffsetRegions[self.comboStep])
  animator.burstParticleEmitter(swooshKey)

  if stance.projectile then
    self:fireProjectiles()
  end

  util.wait(stance.duration, function()
    local damageArea = partDamageArea("swoosh")
    self.weapon:setDamage(self.stepDamageConfig[self.comboStep], damageArea)
  end)

  if self.comboStep < self.comboSteps then
    self.comboStep = self.comboStep + 1
    self:setState(self.wait)
  else
    self.cooldownTimer = self.cooldowns[self.comboStep]
    self.comboStep = 1
  end
end

function MeleeCombo:shouldActivate()
  if self.cooldownTimer == 0 and (self.energyUsage == 0 or not status.resourceLocked("energy")) then
    if self.comboStep > 1 then
      return self.edgeTriggerTimer > 0
    else
      return self.fireMode == (self.activatingFireMode or self.abilitySlot)
    end
  end
end

function MeleeCombo:readyFlash()
  animator.setGlobalTag("bladeDirectives", self.flashDirectives)
  self.flashTimer = self.flashTime
end

function MeleeCombo:computeDamageAndCooldowns()
  local attackTimes = {}
  for i = 1, self.comboSteps do
    local attackTime = self.stances["windup"..i].duration + self.stances["fire"..i].duration
    if self.stances["preslash"..i] then
      attackTime = attackTime + self.stances["preslash"..i].duration
    end
    table.insert(attackTimes, attackTime)
  end

  self.cooldowns = {}
  local totalAttackTime = 0
  local totalDamageFactor = 0
  for i, attackTime in ipairs(attackTimes) do
    self.stepDamageConfig[i] = util.mergeTable(copy(self.damageConfig), self.stepDamageConfig[i])
    self.stepDamageConfig[i].timeoutGroup = "primary"..i

    local damageFactor = self.stepDamageConfig[i].baseDamageFactor
    self.stepDamageConfig[i].baseDamage = damageFactor * self.baseDps * self.fireTime

    totalAttackTime = totalAttackTime + attackTime
    totalDamageFactor = totalDamageFactor + damageFactor

    local targetTime = totalDamageFactor * self.fireTime
    local speedFactor = 1.0 * (self.comboSpeedFactor ^ i)
    table.insert(self.cooldowns, (targetTime - totalAttackTime) * speedFactor)
  end
end

function MeleeCombo:fireProjectiles()
  if not self.projectileType or not status.overConsumeResource("energy", self.projectileEnergyCost or 0) then
    return
  end

  local projectileParams = copy(self.projectileParams)
  projectileParams.powerMultiplier = activeItem.ownerPowerMultiplier()^0.5
  projectileParams.damageKind = self.damageConfig.damageSourceKind
  projectileParams.timeToLive = 1 + (self.hitTimer / 20)
  projectileParams.subterfuge = status.statPositive("ivrpgucbloodseeker") and self.aetherPowerMultiplier
  world.spawnProjectile(self.projectileType, vec2.add(mcontroller.position(), activeItem.handPosition()), activeItem.ownerEntityId(), {mcontroller.facingDirection(), 0}, false, projectileParams)

end

function MeleeCombo:uninit()
  self.weapon:setDamage()
end

function uninit()
  status.clearPersistentEffects("ivrpgwaether" .. activeItem.hand())
  self.weapon:uninit()
end
