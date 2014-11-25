local addonName, addonTable = ...
local L = LibStub("AceLocale-3.0"):GetLocale(addonName, true)
local InTable
InTable = function(table, item)
  for k, v in ipairs(table) do
    if v == item then
      return true
    end
  end
  return false
end
local requiredFollowers = { }
local RemoveFromTable
RemoveFromTable = function(table, toRemove)
  local result = { }
  for k, v in ipairs(table) do
    if not (InTable(toRemove, v)) then
      result[k] = v
    end
  end
  return result
end
local Follower
do
  local _base_0 = {
    Create = function(self, followerIDorInfo)
      if type(followerIDorInfo) == "table" then
        self.info = followerIDorInfo
      else
        self.info = C_Garrison.GetFollowerInfo(followerIDorInfo)
      end
      self.id = self.info.followerID
      self:CacheCounterAbilities()
      return self
    end,
    IsAvailable = function(self, useRequired)
      return self.info.isCollected and self.info.status == nil and (useRequired or #requiredFollowers[self.id] == 0)
    end,
    CanCounter = function(self, abilityName)
      return self.counters[abilityName]
    end,
    CanCounterAny = function(self, abilities)
      for i, ability in ipairs(abilities) do
        if self.counters[ability] then
          return true
        end
      end
      return false
    end,
    AbilitiesCanCounter = function(self, abilities)
      local countered = { }
      for i, ability in ipairs(abilities) do
        if self.counters[ability] then
          table.insert(countered, ability)
        end
      end
      return countered
    end,
    CacheCounterAbilities = function(self)
      local abilities = C_Garrison.GetFollowerAbilities(self.id)
      self.counters = { }
      for i, ability in ipairs(abilities) do
        for j, counter in pairs(ability.counters) do
          self.counters[counter.name] = true
        end
      end
    end,
    LevelScore = function(self, mission)
      local lvlDiff = self.info.level - mission.info.level
      local score = 0
      if lvlDiff < -2 then
        score = -100
      end
      if lvlDiff >= -2 and lvlDiff < 0 then
        score = lvlDiff * -5
      end
      if lvlDiff >= 0 then
        score = math.min(lvlDiff * 3 + 15, 24)
      end
      return score
    end,
    LevelScoreForFiller = function(self, mission)
      local lvlDiff = self.info.level - mission.info.level
      if lvlDiff > 0 then
        return 0
      else
        return lvlDiff
      end
    end,
    ScoreForMission = function(self, mission, mechanics)
      local score = 0
      score = score + self:LevelScore(mission)
      local counters = self:AbilitiesCanCounter(mechanics)
      score = score + #counters * 33
      return score, counters
    end
  }
  _base_0.__index = _base_0
  local _class_0 = setmetatable({
    __init = function() end,
    __base = _base_0,
    __name = "Follower"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Follower = _class_0
end
local Mission
do
  local _base_0 = {
    Create = function(self, mission)
      self.info = mission
      self.id = self.info.missionID
      self:CacheMechanics()
      return self
    end,
    CacheMechanics = function(self)
      self.mechanics = { }
      local location, xp, environment, environmentDesc, environmentTexture, locPrefix, isExhausting, enemies = C_Garrison.GetMissionInfo(self.id)
      for i, enemy in ipairs(enemies) do
        for j, mechanic in pairs(enemy.mechanics) do
          table.insert(self.mechanics, mechanic.name)
        end
      end
    end,
    FindPartyMember = function(self, followers, uncounteredMechanics, useRequired)
      local bestScore = -100
      local bestCandidate = nil
      local bestCounters = nil
      for i, follower in ipairs(followers) do
        local score, counters = follower:ScoreForMission(self, uncounteredMechanics)
        if score > bestScore and follower:IsAvailable(useRequired) then
          bestCounters = counters
          bestCandidate = follower
          bestScore = score
        end
      end
      return bestCandidate, bestCounters
    end,
    FindFiller = function(self, followers, used)
      local bestScore = -100
      local bestCandidate = nil
      for i, follower in ipairs(followers) do
        if follower:IsAvailable(false) and not used[follower.id] then
          local score = follower:LevelScoreForFiller(self)
          if score > bestScore then
            bestCandidate = follower
            bestScore = score
          end
        end
      end
      if bestCandidate == nil then
        for i, follower in ipairs(followers) do
          if follower:IsAvailable(true) and not used[follower.id] then
            local score = follower:LevelScoreForFiller(self)
            if score > bestScore then
              bestCandidate = follower
              bestScore = score
            end
          end
        end
      end
      return bestCandidate
    end,
    FindFillers = function(self, followers)
      local used = { }
      for i, member in ipairs(self.party) do
        used[member.id] = member
      end
      for i = 1, self.info.numFollowers - #self.party do
        do
          local filler = self:FindFiller(followers, used)
          if filler then
            table.insert(self.party, filler)
            used[filler.id] = true
          end
        end
      end
    end,
    FindPriorityParty = function(self, followers)
      local party = { }
      local uncounteredMechanics = self.mechanics
      local safePad = 0
      while true do
        local follower, counters = self:FindPartyMember(followers, uncounteredMechanics, false)
        if follower and #uncounteredMechanics > 0 and #counters == 0 then
          follower, counters = self:FindPartyMember(followers, uncounteredMechanics, true)
        end
        if counters and #counters > 0 then
          table.insert(party, follower)
          uncounteredMechanics = RemoveFromTable(uncounteredMechanics, counters)
          if #uncounteredMechanics == 0 then
            break
          end
        end
        if not follower or #counters == 0 then
          break
        end
        safePad = safePad + 1
        if safePad > 1000 then
          print("Safe pad!!")
          return { }
        end
      end
      return party
    end,
    AffectedMissions = function(self)
      local affectedMissions = { }
      for i, member in ipairs(self.party) do
        for j, mission in ipairs(requiredFollowers[member.id]) do
          if not (mission.id == self.id) then
            table.insert(affectedMissions, mission)
          end
        end
      end
      return affectedMissions
    end,
    GetChance = function(self)
      for i, member in ipairs(self.party) do
        C_Garrison.AddFollowerToMission(self.id, member.id)
      end
      local _, successChance
      _, _, _, successChance = C_Garrison.GetPartyMissionInfo(self.id)
      for i, member in ipairs(self.party) do
        C_Garrison.RemoveFollowerFromMission(self.id, member.id)
      end
      return successChance
    end,
    Start = function(self)
      for i, member in ipairs(self.party) do
        C_Garrison.AddFollowerToMission(self.id, member.id)
      end
      C_Garrison.StartMission(self.id)
      PlaySound("UI_Garrison_CommandTable_MissionStart")
      GarrisonMissionList_UpdateMissions()
      return GarrisonFollowerList_UpdateFollowers(GarrisonMissionFrame.FollowerList)
    end
  }
  _base_0.__index = _base_0
  local _class_0 = setmetatable({
    __init = function() end,
    __base = _base_0,
    __name = "Mission"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Mission = _class_0
end
local MissionPossible = LibStub("AceAddon-3.0"):NewAddon("MissionPossible", "AceHook-3.0")
MissionPossible.OnInitialize = function(self)
  self:SecureHook("GarrisonMissionPage_ShowMission", "ShowMission")
  self:SecureHook("GarrisonMissionList_UpdateMissions", "UpdateMissions")
  self:SecureHook("GarrisonMissionList_Update", "MissionListUpdate")
  self:SecureHook("GarrisonMissionPage_Close", "UpdateMissions")
  return self:SecureHook("HybridScrollFrame_Update", "ScrollHook")
end
MissionPossible.UpdateMissions = function(self)
  self:UpdateFollowers()
  self.missions = { }
  requiredFollowers = { }
  for i, follower in ipairs(self.followers) do
    requiredFollowers[follower.id] = { }
  end
  local availableMissions = C_Garrison.GetAvailableMissions()
  table.sort(availableMissions, function(a, b)
    return a.level < b.level
  end)
  for i, missionInfo in ipairs(availableMissions) do
    local mission = Mission():Create(missionInfo)
    mission.party = mission:FindPriorityParty(self.followers)
    for i, member in ipairs(mission.party) do
      table.insert(requiredFollowers[member.id], mission)
    end
    self.missions[mission.id] = mission
  end
  for id, mission in pairs(self.missions) do
    mission:FindFillers(self.followers)
    mission.chance = mission:GetChance()
  end
  return self:MissionListUpdate()
end
MissionPossible.ScrollHook = function(self, frame)
  local window = GarrisonMissionFrame.MissionTab.MissionList
  if frame == window.listScroll then
    return self:RedrawButtons()
  end
end
MissionPossible.MissionListUpdate = function(self)
  return self:RedrawButtons()
end
MissionPossible.RedrawButtons = function(self)
  local window = GarrisonMissionFrame.MissionTab.MissionList
  local buttons = window.listScroll.buttons
  for i, button in ipairs(buttons) do
    self:CreateButton(button)
  end
end
MissionPossible.ShowMission = function(self, missionInfo)
  local mission = self.missions[missionInfo.missionID]
  local party = mission.party
  for i, member in ipairs(party) do
    GarrisonMissionPage_AddFollower(member.id)
  end
end
MissionPossible.UpdateFollowers = function(self)
  local followers = C_Garrison.GetFollowers()
  self.followers = { }
  for i, follower in ipairs(followers) do
    table.insert(self.followers, Follower():Create(follower))
    if not (requiredFollowers[follower.followerID]) then
      requiredFollowers[follower.followerID] = { }
    end
  end
  return table.sort(self.followers, function(a, b)
    return a.info.level < b.info.level
  end)
end
MissionPossible.CreateButton = function(self, parentButton)
  if not (self.missions) then
    return 
  end
  local mission = self.missions[parentButton.info.missionID]
  if not (mission) then
    return 
  end
  if parentButton.Rewards[1] then
    parentButton.Rewards[1]:SetPoint("RIGHT", parentButton, "RIGHT", -65, 0)
  end
  local button = parentButton.mpButton
  if not (button) then
    button = CreateFrame("Button", nil, parentButton, "UIPanelButtonTemplate")
    parentButton.mpButton = button
    button:SetWidth(60)
    button:SetHeight(25)
    button:SetPoint("RIGHT", parentButton, "RIGHT", -10, 0)
  end
  local affectedMissions = mission:AffectedMissions()
  if #affectedMissions > 0 then
    button:SetText(tostring(mission.chance) .. "% !!!")
  else
    button:SetText(tostring(mission.chance) .. "%")
  end
  button:SetScript("OnClick", function(self)
    return mission:Start()
  end)
  button:SetScript("OnEnter", function(self)
    local difficulty = 'impossible'
    if (mission.chance > 64) then
      difficulty = 'standard'
    elseif (mission.chance > 49) then
      difficulty = 'difficult'
    elseif (mission.chance > 34) then
      difficulty = 'verydifficult'
    end
    local color = QuestDifficultyColors[difficulty]
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(mission.info.name, 1, 1, 1)
    GameTooltip:AddLine("\n" .. tostring(L['Chance']) .. " " .. tostring(mission.chance) .. "%", color.r, color.g, color.b)
    GameTooltip:AddLine("\n" .. tostring(L['Followers']))
    for i, member in ipairs(mission.party) do
      GameTooltip:AddLine("   " .. tostring(member.info.name) .. " (" .. tostring(member.info.level) .. tostring(L['LVL']) .. ")", 1, 1, 1)
    end
    if #affectedMissions > 0 then
      GameTooltip:AddLine("\n" .. tostring(L['AffectedMissions']))
      for j, mission in ipairs(affectedMissions) do
        GameTooltip:AddLine("  " .. tostring(mission.info.name) .. " (" .. tostring(mission.chance) .. "%)", 1, 0, 0)
      end
    end
    return GameTooltip:Show()
  end)
  return button:SetScript("OnLeave", function(self)
    return GameTooltip:Hide()
  end)
end
