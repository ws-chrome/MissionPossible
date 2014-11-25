addonName, addonTable = ...

L = LibStub("AceLocale-3.0")\GetLocale(addonName, true)

-- MP  = LibStub("AceAddon-3.0")\NewAddon("MissionPossible", "AceEvent-3.0", "AceHook-3.0")
InTable = (table, item) ->
  for k, v in ipairs(table)
    return true if v == item
  return false

requiredFollowers = {}

RemoveFromTable = (table, toRemove) ->
  result = {}
  for k, v in ipairs(table)
    result[k] = v unless InTable(toRemove, v)
  return result


class Follower
  Create: (followerIDorInfo) =>
    if type(followerIDorInfo) == "table"
      @info = followerIDorInfo
    else
      @info = C_Garrison.GetFollowerInfo(followerIDorInfo)

    @id = @info.followerID

    @CacheCounterAbilities()
    self

  IsAvailable: (useRequired) =>
    @info.isCollected and @info.status == nil and (useRequired or #requiredFollowers[@id] == 0)

  CanCounter: (abilityName) =>
    return @counters[abilityName]

  CanCounterAny: (abilities) =>
    for i, ability in ipairs(abilities)
      return true if @counters[ability]
    return false

  AbilitiesCanCounter: (abilities) =>
    countered = {}
    for i, ability in ipairs(abilities)
      table.insert(countered, ability) if @counters[ability]
    countered

  CacheCounterAbilities: =>
    abilities = C_Garrison.GetFollowerAbilities(@id)
    @counters = {}
    for i, ability in ipairs(abilities)
      for j, counter in pairs(ability.counters)
        @counters[counter.name] = true


  LevelScore: (mission) =>
    lvlDiff = @info.level - mission.info.level
    score = 0
    if lvlDiff < -2
      score = -100

    if lvlDiff >= -2 and lvlDiff < 0
      score = lvlDiff * -5

    if lvlDiff >= 0
      score = math.min(lvlDiff * 3 + 15, 24)

    return score

  LevelScoreForFiller: (mission) =>
    lvlDiff = @info.level - mission.info.level
    return if lvlDiff > 0 then 0 else lvlDiff

  ScoreForMission: (mission, mechanics) =>
    score = 0

    -- +4+++      = +24%
    -- +3         = +24%
    -- +2         = +21%
    -- +1 lvl     = +18%
    -- same level = +15% (+16)
    -- -1 lvl     = +10%
    -- -2 lvl     = +5%
    -- -3 lvl     = 0

    score += @LevelScore(mission)

    -- -1 lvl + counter = 78 - 45 = 33% ( 43% )
    -- counter = 33% for 2 men mission


    -- score += (@info.level - mission.info.level) * 5 if @info.level <= mission.info.level
    counters = @AbilitiesCanCounter(mechanics)

    score += #counters * 33
    return score, counters


class Mission
  Create: (mission) =>
    @info = mission
    @id = @info.missionID    
    @CacheMechanics()
    self

  CacheMechanics: =>
    @mechanics = {}
    location, xp, environment, environmentDesc, environmentTexture, locPrefix, isExhausting, enemies = C_Garrison.GetMissionInfo(@id)
    for i, enemy in ipairs(enemies) do
      for j, mechanic in pairs(enemy.mechanics)
        table.insert(@mechanics, mechanic.name)

  FindPartyMember: (followers, uncounteredMechanics, useRequired) =>
    bestScore = -100
    bestCandidate = nil
    bestCounters = nil

    for i, follower in ipairs(followers)
      score, counters = follower\ScoreForMission(self, uncounteredMechanics)
      if score > bestScore and follower\IsAvailable(useRequired)
        bestCounters = counters
        bestCandidate = follower
        bestScore = score

    return bestCandidate, bestCounters

  FindFiller: (followers, used) =>
    bestScore = -100
    bestCandidate = nil

    for i, follower in ipairs(followers)
      if follower\IsAvailable(false) and not used[follower.id]
        score = follower\LevelScoreForFiller(self)
        if score > bestScore
          bestCandidate = follower
          bestScore = score

    if bestCandidate == nil
      for i, follower in ipairs(followers)
        if follower\IsAvailable(true) and not used[follower.id]
          score = follower\LevelScoreForFiller(self)
          if score > bestScore
            bestCandidate = follower
            bestScore = score

    return bestCandidate

  FindFillers: (followers) =>
    used = {}

    for i, member in ipairs(@party)
      used[member.id] = member

    for i = 1, @info.numFollowers - #@party
      if filler = @FindFiller(followers, used)
        table.insert(@party, filler) 
        used[filler.id] = true

  FindPriorityParty: (followers) =>
    party = {}
    uncounteredMechanics = @mechanics

    safePad = 0

    while true
      -- find free followers
      follower, counters = @FindPartyMember(followers, uncounteredMechanics, false)

      -- if there is not free who can counter, then find busy one
      if follower and #uncounteredMechanics > 0 and #counters == 0
        follower, counters = @FindPartyMember(followers, uncounteredMechanics, true)

      -- if we found useful follower
      if counters and #counters > 0
        table.insert(party, follower)
        uncounteredMechanics = RemoveFromTable(uncounteredMechanics, counters)
        -- no mechanics to counter, party is complete
        break if #uncounteredMechanics == 0

      break if not follower or #counters == 0

      safePad += 1
      if safePad > 1000
        print "Safe pad!!"
        return {}

    return party

  AffectedMissions: =>
    affectedMissions = {}
    for i, member in ipairs(@party)
      for j, mission in ipairs(requiredFollowers[member.id])
        table.insert(affectedMissions, mission) unless mission.id == @id
    return affectedMissions

  GetChance: =>
    for i, member in ipairs(@party)
      C_Garrison.AddFollowerToMission(@id, member.id)
    
    _, _, _, successChance = C_Garrison.GetPartyMissionInfo(@id)

    for i, member in ipairs(@party)
      C_Garrison.RemoveFollowerFromMission(@id, member.id)  
      
    return successChance

  Start: =>
    for i, member in ipairs(@party)
      C_Garrison.AddFollowerToMission(@id, member.id)
    C_Garrison.StartMission(@id)
    PlaySound("UI_Garrison_CommandTable_MissionStart")
    GarrisonMissionList_UpdateMissions()
    GarrisonFollowerList_UpdateFollowers(GarrisonMissionFrame.FollowerList)


MissionPossible = LibStub("AceAddon-3.0")\NewAddon("MissionPossible", "AceHook-3.0")

MissionPossible.OnInitialize = =>
  @SecureHook("GarrisonMissionPage_ShowMission", "ShowMission")
  @SecureHook("GarrisonMissionList_UpdateMissions", "UpdateMissions")
  @SecureHook("GarrisonMissionList_Update", "MissionListUpdate")
  @SecureHook("GarrisonMissionPage_Close", "UpdateMissions")
  @SecureHook("HybridScrollFrame_Update", "ScrollHook")



MissionPossible.UpdateMissions = =>
  @UpdateFollowers()

  @missions = {}
  requiredFollowers = {}
  for i, follower in ipairs(@followers)
    requiredFollowers[follower.id] = {}

  availableMissions = C_Garrison.GetAvailableMissions()
  table.sort(availableMissions, (a, b) -> a.level < b.level)

  for i, missionInfo in ipairs(availableMissions)
    mission = Mission!\Create(missionInfo)
    mission.party  = mission\FindPriorityParty(@followers)
    for i, member in ipairs(mission.party)
      table.insert(requiredFollowers[member.id], mission)

    @missions[mission.id] = mission

  for id, mission in pairs(@missions)
    mission\FindFillers(@followers)
    mission.chance = mission\GetChance()

  @MissionListUpdate()


MissionPossible.ScrollHook = (frame) =>
  window  = GarrisonMissionFrame.MissionTab.MissionList
  if frame == window.listScroll
    @RedrawButtons()

MissionPossible.MissionListUpdate = =>
  @RedrawButtons()


MissionPossible.RedrawButtons = =>
  window  = GarrisonMissionFrame.MissionTab.MissionList
  buttons = window.listScroll.buttons
  for i, button in ipairs(buttons)
    @CreateButton(button)


MissionPossible.ShowMission = (missionInfo) =>
  mission = @missions[missionInfo.missionID]
  party   = mission.party
  for i, member in ipairs(party)
    GarrisonMissionPage_AddFollower(member.id)


MissionPossible.UpdateFollowers = =>
  followers = C_Garrison.GetFollowers()
  @followers = {}
  for i, follower in ipairs(followers) 
    table.insert(@followers, Follower!\Create(follower))
    requiredFollowers[follower.followerID] = {} unless requiredFollowers[follower.followerID]

  table.sort(@followers, (a, b) -> a.info.level < b.info.level)


MissionPossible.CreateButton = (parentButton) =>
  return unless @missions

  mission = @missions[parentButton.info.missionID]
  return unless mission

  parentButton.Rewards[1]\SetPoint("RIGHT", parentButton, "RIGHT", -65, 0) if parentButton.Rewards[1]
  button = parentButton.mpButton

  unless button
    button = CreateFrame("Button", nil, parentButton, "UIPanelButtonTemplate")
    parentButton.mpButton = button
    button\SetWidth(60)
    button\SetHeight(25)
    button\SetPoint("RIGHT", parentButton, "RIGHT", -10, 0)

  affectedMissions = mission\AffectedMissions()
  if #affectedMissions > 0
    button\SetText("#{mission.chance}% !!!")
  else
    button\SetText("#{mission.chance}%")

  button\SetScript "OnClick", => 
    mission\Start()

  button\SetScript "OnEnter", =>

    difficulty = 'impossible'
    if (mission.chance > 64)
      difficulty = 'standard'
    elseif (mission.chance > 49)
      difficulty = 'difficult'
    elseif (mission.chance > 34)
      difficulty = 'verydifficult'

    color = QuestDifficultyColors[difficulty]

    GameTooltip\SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip\SetText(mission.info.name, 1, 1, 1)

    GameTooltip\AddLine("\n#{L['Chance']} #{mission.chance}%", color.r, color.g, color.b)

    GameTooltip\AddLine("\n#{L['Followers']}")
    for i, member in ipairs(mission.party)
      GameTooltip\AddLine("   #{member.info.name} (#{member.info.level}#{L['LVL']})", 1, 1, 1)

    if #affectedMissions > 0
      GameTooltip\AddLine("\n#{L['AffectedMissions']}")
      for j, mission in ipairs(affectedMissions)
        GameTooltip\AddLine("  #{mission.info.name} (#{mission.chance}%)", 1, 0, 0)

    GameTooltip\Show()

  button\SetScript "OnLeave", =>
    GameTooltip\Hide()
