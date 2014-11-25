addonName, addonTable = ...


AL3 = LibStub("AceLocale-3.0")
L = AL3\NewLocale(addonName, "enUS", true, false)

if L
  L["StartMission"] = "Start"
  L["Chance"] = "Success rate is"
  L["Followers"] = "Followers:"
  L["AffectedMissions"] = "Will reduce chances of:"
  L["LVL"] = "lvl"


L = AL3\NewLocale(addonName, "ruRU")

if L
  L["StartMission"] = "Начать"
  L["Chance"] = "Шанс успеха"
  L["Followers"] = "Соратники:"
  L["AffectedMissions"] = "Снизит шанс выполнения:"
  L["LVL"] = " ур."
