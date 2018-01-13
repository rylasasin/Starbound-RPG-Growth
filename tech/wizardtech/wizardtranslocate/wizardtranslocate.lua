require "/scripts/keybinds.lua"

function init()
  self.dashCooldownTimer = 0
  self.rechargeEffectTimer = 0

  self.cost = config.getParameter("cost")
  self.dashMaxDistance = config.getParameter("dashDistance")
  self.dashCooldown = config.getParameter("dashCooldown")
  --sb.logInfo("ConfigCooldown: " .. tostring(self.dashCooldown))
  self.rechargeDirectives = config.getParameter("rechargeDirectives", "?fade=B880FCFF=0.25")
  self.rechargeEffectTime = config.getParameter("rechargeEffectTime", 0.1)

  Bind.create("g", translocate)
end

function translocate()
  --sb.logInfo("Cooldown: " .. tostring(self.dashCooldownTimer))
  local isNotMissionWorld = ((world.terrestrial() or world.type() == "outpost" or world.type() == "scienceoutpost") and world.dayLength() ~= 100000) or status.statPositive("admin")
  local notThroughWalls = not world.lineTileCollision(tech.aimPosition(), mcontroller.position())
  if self.dashCooldownTimer == 0 and not status.statPositive("activeMovementAbilities") and (isNotMissionWorld or notThroughWalls) and status.overConsumeResource("energy", 1) then
    local agility = world.entityCurrency(entity.id(),"agilitypoint") or 1
    local distance = world.magnitude(tech.aimPosition(), mcontroller.position())
    local costPercent = -(1.06^(distance-agility)+20.0)/100.0
    status.modifyResourcePercentage("energy", costPercent)
    local projectileId = world.spawnProjectile(
        "invtransdisc",
        tech.aimPosition(),
        entity.id(),
        {0,0},
        false
      )
    --sb.logInfo("projectile created: " .. tostring(projectileId)) 
    if projectileId then
      world.callScriptedEntity(projectileId, "setOwnerId", entity.id())
      status.setStatusProperty("translocatorDiscId", projectileId)
      status.addEphemeralEffect("translocate")
      self.dashCooldownTimer = self.dashCooldown
    end
  end
end

function uninit()
  tech.setParentDirectives()
end

function update(args)
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
end
