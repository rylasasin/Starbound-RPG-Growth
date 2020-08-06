require "/scripts/util.lua"
require "/scripts/interp.lua"
require "/scripts/vec2.lua"
require "/scripts/ivrpgutil.lua"

-- Base gun fire ability
GunFire = WeaponAbility:new()

function GunFire:init()
  message.setHandler("killedEnemyDeadshot", function(_, _, enemyLevel, damageKind, bledToDeath)
    if bledToDeath and bledToDeath == "lotusbullet" then
      activeItem.setInstanceValue("powered", true)
    elseif damageKind == "lotusbullet" then
      self.energyMultiplier = math.min(self.energyMultiplier + 0.05, 0.5)
    end
  end)

  self.weapon:setStance(self.stances.idle)

  self.cooldownTimer = self.fireTime
  self.energyMultiplier = 0

  self.weapon.onLeaveAbility = function()
    self.weapon:setStance(self.stances.idle)
  end
end

function GunFire:update(dt, fireMode, shiftHeld)
  WeaponAbility.update(self, dt, fireMode, shiftHeld)

  self.cooldownTimer = math.max(0, self.cooldownTimer - self.dt)

  if animator.animationState("firing") ~= "fire" then
    animator.setLightActive("muzzleFlash", false)
  end

  if self.fireMode == (self.activatingFireMode or self.abilitySlot)
    and not self.weapon.currentAbility
    and self.cooldownTimer == 0
    and not status.resourceLocked("energy")
    and not world.lineTileCollision(mcontroller.position(), self:firePosition()) then

    if status.overConsumeResource("energy", self:energyPerShot()) then
      self:setState(self.auto)
    end

  elseif self.fireMode == "alt"
    and not self.weapon.currentAbility
    and self.cooldownTimer == 0
    and not status.resourceLocked("energy")
    and not world.lineTileCollision(mcontroller.position(), vec2.add(mcontroller.position(), {mcontroller.facingDirection() * 7, 0.25}))
    and mcontroller.groundMovement() then

      self:setState(self.burst)

  end

  self.accurateFire = mcontroller.crouching()
end

function GunFire:auto()
  self.weapon:setStance(self.stances.fire)

  self:fireProjectile()
  self:muzzleFlash()

  if self.stances.fire.duration then
    util.wait(self.stances.fire.duration)
  end

  self.cooldownTimer = self.fireTime
  self:setState(self.cooldown)
end

function GunFire:burst()
  self.weapon:setStance(self.stances.charge)
  self.weapon:updateAim()

  animator.setAnimationState("charge", "on")
  animator.playSound("charging")
  local progress = 0
  local from = self.weapon.aimAngle
  while self.fireMode == "alt" and progress < 1 do
    mcontroller.controlModifiers({movementSuppressed = true, jumpingSuppressed = true})
    self.weapon.aimAngle = interp.linear(progress, from, 0)
    self.weapon:updateAim()
    progress = math.min(1.0, progress + (self.dt / 0.5))
    coroutine.yield()
  end

  if progress ~= 1 then
    animator.setAnimationState("charge", "off")
    animator.stopAllSounds("charging")
    return
  end

  local params = {}
  params.power = 5
  params.powerMultiplier = activeItem.ownerPowerMultiplier()
  params.speed = 80
  projectileType = "ivrpgbreathlessbeam"
  firePosition = self:firePosition(0.15)
  self.timer = 0.1
  self.direction = false
  local directions = {-4, -2, 0, 2, 4}
  while self.fireMode == "alt" and mcontroller.groundMovement() and status.resource("energy") >= 30 do
    mcontroller.controlModifiers({movementSuppressed = true, jumpingSuppressed = true})
    if self.timer <= 0 then
      if #directions == 0 then directions = {-4, -2, 0, 2, 4} end
      self.index = math.random(#directions)
      self.direction = directions[self.index]
      table.remove(directions, self.index)
      animator.playSound("laser")
      status.overConsumeResource("energy", 20)
      self.timer = 0.15
    end
    self.timer = self.timer - self.dt
    params.timeToLive = 0.5
    params.curveDirection = self.direction
    if self.direction then
      firePosition = self:firePosition(0.15)
      world.spawnProjectile(projectileType, firePosition, activeItem.ownerEntityId(), {mcontroller.facingDirection(), 0}, false, params)
    end
    coroutine.yield()
  end

  animator.setAnimationState("charge", "discharge")
  animator.playSound("discharge")
  util.wait(0.25, function() mcontroller.controlModifiers({movementSuppressed = true, jumpingSuppressed = true}) end)

  self.cooldownTimer = self.fireTime
  animator.setAnimationState("charge", "off")
  --self:setState(self.cooldown)
end

function GunFire:cooldown()
  self.weapon:setStance(self.stances.cooldown)
  self.weapon:updateAim()

  local progress = 0
  util.wait(self.stances.cooldown.duration, function()
    local from = self.stances.cooldown.weaponOffset or {0,0}
    local to = self.stances.idle.weaponOffset or {0,0}
    self.weapon.weaponOffset = {interp.linear(progress, from[1], to[1]), interp.linear(progress, from[2], to[2])}

    self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(progress, self.stances.cooldown.weaponRotation, self.stances.idle.weaponRotation))
    self.weapon.relativeArmRotation = util.toRadians(interp.linear(progress, self.stances.cooldown.armRotation, self.stances.idle.armRotation))

    progress = math.min(1.0, progress + (self.dt / self.stances.cooldown.duration))
  end)
end

function GunFire:muzzleFlash()
  animator.setPartTag("muzzleFlash", "variant", math.random(1, self.muzzleFlashVariants or 3))
  animator.setAnimationState("firing", "fire")
  animator.burstParticleEmitter("muzzleFlash")
  animator.playSound("fire")

  animator.setLightActive("muzzleFlash", true)
end

function GunFire:fireBeam(projectileType, projectileParams, inaccuracy, firePosition, projectileCount)

end

function GunFire:fireProjectile(projectileType, projectileParams, inaccuracy, firePosition, projectileCount)
  local params = sb.jsonMerge(self.projectileParameters, projectileParams or {})
  params.power = params.power or self:damagePerShot()
  params.powerMultiplier = activeItem.ownerPowerMultiplier()
  params.speed = util.randomInRange(params.speed)

  if not projectileType then
    projectileType = self.projectileType
  end
  if type(projectileType) == "table" then
    projectileType = projectileType[math.random(#projectileType)]
  end

  local projectileId = 0
  for i = 1, (projectileCount or self.projectileCount) do
    if params.timeToLive then
      params.timeToLive = util.randomInRange(params.timeToLive)
    end

    projectileId = world.spawnProjectile(
      projectileType,
      firePosition or self:firePosition(),
      activeItem.ownerEntityId(),
      self:aimVector(self.accurateFire and 0 or (innacuracy or self.inaccuracy)),
      false,
      params
      )
  end
  return projectileId
end

function GunFire:firePosition(xOffset)
  local offset = copy(self.weapon.muzzleOffset)
  offset[2] = 0.5
  offset[1] = offset[1] - 0.5 - (xOffset or 0)
  return vec2.add(mcontroller.position(), activeItem.handPosition(offset))
end

function GunFire:aimVector(inaccuracy)
  local aimVector = vec2.rotate({1, 0}, self.weapon.aimAngle + sb.nrand(inaccuracy, 0))
  aimVector[1] = aimVector[1] * mcontroller.facingDirection()
  return aimVector
end

function GunFire:energyPerShot()
  return self.energyUsage * self.fireTime * (self.energyUsageMultiplier or 1.0)
end

function GunFire:damagePerShot()
  local powered = config.getParameter("powered", false)
  activeItem.setInstanceValue("powered", false)
  return (self.baseDamage or (self.baseDps * self.fireTime)) * (self.baseDamageMultiplier or 1.0) * config.getParameter("damageLevelMultiplier") / self.projectileCount * (powered and 1.25 or 1)
end

function GunFire:uninit()

end
