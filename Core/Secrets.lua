local _, ns = ...

-- Inside restricted content the client hands addons secret values for unit identity. Every read of a unit's name or identity goes through these guards.

-- canaccessvalue is SecretArguments = "AllowedWhenUntainted" (FrameScriptDocumentation.lua:68), so tainted addon code handing it a secret may raise instead of answering; the pcall turns that raise into "not accessible", the only safe reading.
function ns.CanAccess(value)
    local ok, accessible = pcall(canaccessvalue, value)
    return ok and accessible == true
end

-- Ask before reading rather than testing the result: UnitIsUnit and UnitInRaid return secret booleans under a restriction, and an if-test on a secret raises in tainted code. UnitExists first, because callers may pass a character name where no unit token exists.
function ns.IdentitySecret(token)
    if not token or not UnitExists(token) then return false end
    return C_Secrets.ShouldUnitIdentityBeSecret(token) == true
end

-- A unit's name, or nil when the client hides it from addons.
function ns.ReadableName(unit)
    if ns.IdentitySecret(unit) then return nil end
    local name = UnitName(unit)
    if not ns.CanAccess(name) then return nil end
    return name
end
