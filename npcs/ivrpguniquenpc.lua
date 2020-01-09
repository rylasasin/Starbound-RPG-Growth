function rpg_initUniqueNPC()
  script.setUpdateDelta(1)
  message.setHandler("addToOwnedMonsters", function(_, _, id)
    table.insert(self.rpg_spawn.activeSummons, id)
  end)
end

function rpg_updateUniqueNPC(dt)
  for k,v in pairs(self.rpg_Actions) do
  	if k == "debuff" then
  	  local targetEntities = friendlyQuery(mcontroller.position(), v.range, {}, self.rpg_ID, true)
  	  if targetEntities then
  	    for _,id in ipairs(targetEntities) do
  	      for _,effect in ipairs(v.statusEffects) do
  	        world.sendEntityMessage(id, "addEphemeralEffect", effect, 1, self.rpg_ID)
  	      end
  	    end
  	  end
  	elseif k == "buff" then
  	  local targetEntities = enemyQuery(mcontroller.position(), v.range, v.self and {} or {withoutEntityId = self.rpg_ID, includedTypes = {"creature"}}, self.rpg_ID, true)
  	  if targetEntities then
  	    for _,id in ipairs(targetEntities) do
  	      for _,effect in ipairs(v.statusEffects) do
  	        world.sendEntityMessage(id, "addEphemeralEffect", effect, 1, self.rpg_ID)
  	      end
  	    end
  	  end
  	elseif k == "tank" then
  	  if self.rpg_armor then
  	    rpg_stripArmor(self.rpg_armor.current == 0)
  	  else
  	    self.rpg_armor = {type = v.type, max = v.protection, current = v.protection, tag = v.segments or 10, rechargeTime = v.rechargeTime, breakTime = v.breakTime, segments = v.segments or 10, elementType = v.elementType or "none"}
  	    status.setStatusProperty("ivrpg_npcShield_element", v.elementType)
      end
      status.addEphemeralEffect("ivrpgNpcShield", math.huge, self.rpg_ID)
  	elseif k == "spawn" then
      if not self.rpg_spawn then
        self.rpg_spawn = {spawnTypes = v.spawnTypes, frequency = v.frequency, spawnLevel = v.spawnLevel, maxActive = v.maxActive, activeSummons = {}, say = v.say, timer = v.frequency}
  	  end
    end
  end

  status.setPersistentEffects("ivrpgUniqueNpc", self.rpg_improvedStats or {})

  if self.rpg_stripTimer and self.rpg_stripTimer > 0 then
    if self.rpg_breakTimer and self.rpg_breakTimer > 0 then
      self.rpg_breakTimer = self.rpg_breakTimer - dt
      status.setStatusProperty("ivrpg_npcShield_tag", tostring(self.rpg_armor.segments + 1))
    else
      local newArmor = math.floor((self.rpg_armor.rechargeTime - self.rpg_stripTimer) / self.rpg_armor.rechargeTime * self.rpg_armor.segments)
      if newArmor ~= self.rpg_armor.tag then
        self.rpg_armor.tag = newArmor
        if newArmor % (self.rpg_armor.segments / 10) == 0 and self.rpg_armor.type ~= "shield" then
          status.setStatusProperty("ivrpg_npcShield_sound", "fillTank2")
        end
      end
      status.setStatusProperty("ivrpg_npcShield_tag", tostring(newArmor))
      self.rpg_stripTimer = self.rpg_stripTimer - dt
      if self.rpg_stripTimer <= 0 then
        self.rpg_armor.current = self.rpg_armor.max
        status.setStatusProperty("ivrpg_npcShield_sound", "tankFull")
      end
    end
  elseif self.rpg_armor then
    status.setStatusProperty("ivrpg_npcShield_tag", tostring(math.ceil(self.rpg_armor.current / self.rpg_armor.max * self.rpg_armor.segments)))
  end

  if status.resource("health") <= 0 then
  	world.spawnTreasure(mcontroller.position(), "experienceorbpoolminiboss", npc.level())
  end

  if self.rpg_spawn then
    rpg_checkSummonsActive()
    if #self.rpg_spawn.activeSummons < self.rpg_spawn.maxActive then
      self.rpg_spawn.timer = math.max(self.rpg_spawn.timer - dt, 0)
      if self.rpg_spawn.timer == 0 then
        rpg_spawnMonster()
      end
    end
  end

end

function rpg_spawnMonster()
  local monster = self.rpg_spawn.spawnTypes[math.random(1, #self.rpg_spawn.spawnTypes)]
  local monsterId = world.spawnMonster(monster, mcontroller.position(), {
    level = self.rpg_spawn.spawnLevel,
    damageTeam = entity.damageTeam().team,
    damageTeamType = entity.damageTeam().type,
    rpgOwnerUuid = self.rpg_ID,
    aggressive = world.entityAggressive(self.rpg_ID)
  })
  if monsterId then
    table.insert(self.rpg_spawn.activeSummons, monsterId)
    npc.say(self.rpg_spawn.say)
    self.rpg_spawn.timer = self.rpg_spawn.frequency
  end
end

function rpg_checkSummonsActive()
  local newSummons = {}
  for _,id in ipairs(self.rpg_spawn.activeSummons) do
    if world.entityExists(id) then
      table.insert(newSummons, id)
    end
  end
  self.rpg_spawn.activeSummons = newSummons
end

function rpg_weaken(weaken)
	status.setPersistentEffects("ivrpgstripArmor", weaken and {
      	{stat="physicalResistance", amount=-0.5},
      	{stat="iceResistance", amount=-0.5},
      	{stat="fireResistance", amount=-0.5},
      	{stat="electricResistance", amount=-0.5},
      	{stat="poisonResistance", amount=-0.5},
      	{stat="novaResistance", amount=-0.5},
      	{stat="demonicResistance", amount=-0.5},
      	{stat="holyResistance", amount=-0.5},
      	{stat="shadowResistance", amount=-0.5},
      	{stat="cosmicResistance", amount=-0.5},
      	{stat="radioactiveResistance", amount=-0.5}
    } or {})
end

function rpg_damage(damage, sourceDamage, sourceKind, sourceId)
  if self.rpg_armor and self.rpg_armor.current ~= 0 then
    if self.rpg_armor.type == "burst" then
      local healthPercent = math.floor(sourceDamage / status.stat("maxHealth") * 100)
      self.rpg_armor.current = math.max(self.rpg_armor.current - math.max(healthPercent, 1), 0)
    elseif self.rpg_armor.type == "rapid" then
      self.rpg_armor.current = math.max(self.rpg_armor.current - 1, 0)
    elseif self.rpg_armor.type == "shield" then
      if string.find(sourceKind, self.rpg_armor.elementType) then
        self.rpg_armor.current = math.max(self.rpg_armor.current - sourceDamage, 0)
      end
    end
    status.modifyResource("health", damage)
    if self.rpg_armor.current == 0 then
    	if self.rpg_armor.type == "rapid" then
      	rpg_rapidSpark()
      end
      self.rpg_stripTimer = self.rpg_armor.rechargeTime
      self.rpg_breakTimer = self.rpg_armor.breakTime
      self.rpg_armor.tag = 0
      status.setStatusProperty("ivrpg_npcShield_sound", "tankEmpty")
      status.setStatusProperty("ivrpg_npcShield_tag", tostring(self.rpg_armor.segments + 1))
    end
  end
end

function rpg_stripArmor(strip)
  status.setPersistentEffects("ivrpgstripArmor", {
    {stat = "poisonStatusImmunity", amount = strip and 0 or 1 },
    {stat = "fireStatusImmunity", amount = strip and 0 or 1 },
    {stat = "electricStatusImmunity", amount = strip and 0 or 1 },
    {stat = "iceStatusImmunity", amount = strip and 0 or 1 },
    {stat = "holyStatusImmunity", amount = strip and 0 or 1 },
    {stat = "demonicStatusImmunity", amount = strip and 0 or 1 },
    {stat = "novaStatusImmunity", amount = strip and 0 or 1 },
    {stat = "cosmicStatusImmunity", amount = strip and 0 or 1 },
    {stat = "radioactiveStatusImmunity", amount = strip and 0 or 1 },
    {stat = "shadowStatusImmunity", amount = strip and 0 or 1 }
  })
end