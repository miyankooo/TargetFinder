local _, ns = ...

-- Every place Classic Era 1.15.x and WoW Forever 1.60.x differ lives here, so a new build is checked against one file. The two share one toc; each difference is detected by feature, never by version number or WOW_PROJECT_ID, which Forever reports as mainline.

-- 1.60 hands out secret values for unit identity inside restricted content; 1.15.9 exposes the same check and never issues a secret, so one guard serves both. On 1.60 canaccessvalue is SecretArguments = "AllowedWhenUntainted" (FrameScriptDocumentation.lua:68), so tainted addon code handing it a secret may raise instead of answering; the pcall turns that raise into "not accessible", the only safe reading. A missing function means a client without secrets.
local function canAccess(value)
    local check = canaccessvalue
    if not check then return true end
    local ok, accessible = pcall(check, value)
    return ok and accessible ~= false
end

ns.CanAccess = canAccess

-- Ask before reading rather than testing the result: on 1.60 UnitIsUnit and UnitInRaid return secret booleans under a restriction, and an if-test on a boolean secret raises in tainted code. Present on both branches, so the guard is not version-gated. UnitExists first, because callers may pass a character name where no unit token exists.
function ns.IdentitySecret(token)
    if not token then return false end
    local shouldBeSecret = C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret
    if not shouldBeSecret then return false end
    if not UnitExists(token) then return false end
    return shouldBeSecret(token) == true
end

-- A unit's name, or nil when the client hides it from addons.
function ns.ReadableName(unit)
    if ns.IdentitySecret(unit) then return nil end
    local name = UnitName(unit)
    if not canAccess(name) then return nil end
    return name
end

-- 1.60 moved the macro caps into Constants.MacroConsts and dropped the MAX_ACCOUNT_MACROS global; 1.15.9 has only the global. Both read 120.
function ns.AccountMacroCap()
    local consts = Constants and Constants.MacroConsts
    return (consts and consts.MAX_ACCOUNT_MACROS) or MAX_ACCOUNT_MACROS or 120
end

-- Bars 1-6 fill slots 1-72 and MultiBar5-7 add 145-180. Both clients define all three extra bars in Shared\MultiActionBars.xml, so one range serves both and an unused slot simply reads back nil.
ns.ACTION_SLOT_COUNT = 180

-- The documented nameplate token range on both clients. Tokens only resolve while a nameplate is actually shown.
ns.MAX_NAMEPLATES = 40

-- SetRaidTargetIconTexture only picks the cell out of the sheet: 1.15.9 sets texcoords, 1.60 calls SetSpriteSheetCell, and neither assigns the file. Blizzard's own frames set it in XML, so any texture the addon creates has to be given the sheet before the first call or the marker never draws.
local RAID_ICON_SHEET = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

function ns.ShowMarkerTexture(texture, marker)
    if not texture or not marker then return end
    texture:SetTexture(RAID_ICON_SHEET)
    SetRaidTargetIconTexture(texture, marker)
    texture:Show()
end
