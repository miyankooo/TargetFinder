local _, ns = ...

-- Inside restricted content the client hands addons secret values for unit identity. Every read of a unit's name or identity goes through these guards.

-- canaccessvalue is SecretArguments = "AllowedWhenUntainted" (FrameScriptDocumentation.lua:68), so tainted addon code handing it a secret may raise instead of answering; the pcall turns that raise into "not accessible", the only safe reading. Its argument is Nilable = false and nil is never secret, so nil is answered without the call, through type() as Blizzard's Dump.lua tests values that may be secret.
function ns.CanAccess(value)
    if type(value) == "nil" then return true end
    local ok, accessible = pcall(canaccessvalue, value)
    return ok and accessible == true
end

-- Ask before reading rather than testing the result: UnitInRaid returns a secret boolean under an identity restriction, and an if-test on a secret raises in tainted code. UnitExists first, because callers may pass a character name where no unit token exists.
function ns.IdentitySecret(token)
    if not token or not UnitExists(token) then return false end
    return C_Secrets.ShouldUnitIdentityBeSecret(token) == true
end

-- UnitIsUnit is SecretWhenUnitComparisonRestricted (UnitDocumentation.lua:2413), a restriction separate from identity, so a comparison is asked about before it runs.
function ns.ComparisonSecret(token, other)
    if not token or not UnitExists(token) then return false end
    return C_Secrets.ShouldUnitComparisonBeSecret(token, other) == true
end

-- A unit's name, or nil when the client hides it from addons.
function ns.ReadableName(unit)
    if ns.IdentitySecret(unit) then return nil end
    local name = UnitName(unit)
    if not ns.CanAccess(name) then return nil end
    return name
end
