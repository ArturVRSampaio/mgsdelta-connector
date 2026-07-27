-- Recon script for mgsdelta-connector milestone 2 ("read one flag").
-- Reads the live BP_KerotanSubsystem_C GameInstanceSubsystem and prints its
-- frog/gako unlock counters to UE4SS.log. Not part of any real mod, just a
-- throwaway probe for this session.

local function ReadKerotanStatus()
    local KerotanSubsystem = FindFirstOf("BP_KerotanSubsystem_C")
    if not KerotanSubsystem or not KerotanSubsystem:IsValid() then
        print("[FrogFlagReader] BP_KerotanSubsystem_C not found\n")
        return
    end

    print(string.format("[FrogFlagReader] Found KerotanSubsystem at %s\n", tostring(KerotanSubsystem:GetAddress())))

    local ok1, GakoStatus = pcall(function() return KerotanSubsystem:GetGakoUnlockStatus() end)
    if ok1 and GakoStatus then
        print(string.format("[FrogFlagReader] GetGakoUnlockStatus -> UnlockCount=%s TotalCount=%s IsExistInCurrentArea=%s IsUnlcokedInCurrentArea=%s\n",
            tostring(GakoStatus.UnlockCount), tostring(GakoStatus.TotalCount),
            tostring(GakoStatus.IsExistInCurrentArea), tostring(GakoStatus.IsUnlcokedInCurrentArea)))
    else
        print(string.format("[FrogFlagReader] GetGakoUnlockStatus call failed: %s\n", tostring(GakoStatus)))
    end

    local ok2, MapStatus = pcall(function() return KerotanSubsystem:GetCurrentMapKerotanStatus() end)
    if ok2 and MapStatus then
        print(string.format("[FrogFlagReader] GetCurrentMapKerotanStatus -> UnlockCount=%s TotalCount=%s IsExistInCurrentArea=%s IsUnlcokedInCurrentArea=%s\n",
            tostring(MapStatus.UnlockCount), tostring(MapStatus.TotalCount),
            tostring(MapStatus.IsExistInCurrentArea), tostring(MapStatus.IsUnlcokedInCurrentArea)))
    else
        print(string.format("[FrogFlagReader] GetCurrentMapKerotanStatus call failed: %s\n", tostring(MapStatus)))
    end

    local ok3, KerotanStatus = pcall(function() return KerotanSubsystem:GetKerotanUnlockStatus() end)
    if ok3 and KerotanStatus then
        print(string.format("[FrogFlagReader] GetKerotanUnlockStatus -> bIsUnlocked=%s bHasKerotan=%s\n",
            tostring(KerotanStatus.bIsUnlocked), tostring(KerotanStatus.bHasKerotan)))
    else
        print(string.format("[FrogFlagReader] GetKerotanUnlockStatus call failed: %s\n", tostring(KerotanStatus)))
    end
end

local function DumpClassMembers(Class)
    if not Class or not Class:IsValid() then return end
    local ok, fullName = pcall(function() return Class:GetFullName() end)
    print(string.format("[FrogFlagReader] -- Members of %s --\n", ok and fullName or "?"))

    Class:ForEachFunction(function(Function)
        local ok2, name = pcall(function() return Function:GetFullName() end)
        print(string.format("[FrogFlagReader]   Function: %s\n", ok2 and name or "?"))
    end)

    Class:ForEachProperty(function(Property)
        local ok3, name = pcall(function() return Property:GetFullName() end)
        print(string.format("[FrogFlagReader]   Property: %s\n", ok3 and name or "?"))
    end)
end

-- Walks the full class hierarchy (Blueprint layer + native parents) since
-- ForEachFunction/ForEachProperty only return members declared at that
-- exact level, not inherited ones.
local function DumpKerotanSubsystemMembers()
    local KerotanSubsystem = FindFirstOf("BP_KerotanSubsystem_C")
    if not KerotanSubsystem or not KerotanSubsystem:IsValid() then
        print("[FrogFlagReader] BP_KerotanSubsystem_C not found for member dump\n")
        return
    end

    local Class = KerotanSubsystem:GetClass()
    local Depth = 0
    while Class and Class:IsValid() and Depth < 10 do
        DumpClassMembers(Class)
        Class = Class:GetSuperStruct()
        Depth = Depth + 1
    end
end

-- Milestone 3 probe: find a live GakoComponent (the per-duck component,
-- /Script/MGS3.GakoComponent) and call GakoSetCollected() on it, to prove
-- the write path works. Reads bColleted before/after plus the aggregate
-- GetGakoUnlockStatus() counter, so we have two independent signals that
-- the write actually took effect.
local function TestGakoWrite()
    local AllGakoComps = FindAllOf("GakoComponent")
    if not AllGakoComps or #AllGakoComps == 0 then
        print("[FrogFlagReader] No GakoComponent instances found\n")
        return
    end

    print(string.format("[FrogFlagReader] Found %d GakoComponent instance(s)\n", #AllGakoComps))

    -- Find one that ISN'T already collected -- testing on an already-true
    -- one (like FindFirstOf grabbed last time) proves nothing.
    local GakoComp = nil
    for _, Comp in ipairs(AllGakoComps) do
        local ok, collected = pcall(function() return Comp.bColleted end)
        local okName2, name2 = pcall(function() return Comp:GetFullName() end)
        print(string.format("[FrogFlagReader]   candidate %s bColleted=%s\n",
            okName2 and name2 or "?", tostring(ok and collected or "?")))
        if ok and collected == false and not GakoComp then
            GakoComp = Comp
        end
    end

    if not GakoComp then
        print("[FrogFlagReader] Every found GakoComponent is already collected -- no uncollected duck available to test the write on\n")
        return
    end

    local okName, fullName = pcall(function() return GakoComp:GetFullName() end)
    print(string.format("[FrogFlagReader] GakoComponent: %s\n", okName and fullName or "?"))

    local okBefore, before = pcall(function() return GakoComp.bColleted end)
    print(string.format("[FrogFlagReader] bColleted BEFORE = %s\n", tostring(okBefore and before or "?")))

    local okCall, err = pcall(function() GakoComp:GakoSetCollected() end)
    print(string.format("[FrogFlagReader] GakoSetCollected() call ok=%s err=%s\n", tostring(okCall), tostring(err)))

    local okAfter, after = pcall(function() return GakoComp.bColleted end)
    print(string.format("[FrogFlagReader] bColleted AFTER = %s\n", tostring(okAfter and after or "?")))

    local KerotanSubsystem = FindFirstOf("BP_KerotanSubsystem_C")
    if KerotanSubsystem and KerotanSubsystem:IsValid() then
        local okStatus, status = pcall(function() return KerotanSubsystem:GetGakoUnlockStatus() end)
        if okStatus and status then
            print(string.format("[FrogFlagReader] Aggregate AFTER write: UnlockCount=%s TotalCount=%s\n",
                tostring(status.UnlockCount), tostring(status.TotalCount)))
        end
    end
end

-- Milestone 3 probe, take 2: GakoSetCollected is a one-shot (already true
-- for whichever duck FindAllOf happened to grab), so it can't prove a write
-- actually changes anything once a duck is already collected. Gako_Life
-- (an IntProperty on the BP_Gako_C actor, not the component) is repeatable
-- and reversible instead -- decrement it, verify, then restore the
-- original value so this probe doesn't leave a lasting change.
local function TestGakoLifeWrite()
    local GakoActor = FindFirstOf("BP_Gako_C")
    if not GakoActor or not GakoActor:IsValid() then
        print("[FrogFlagReader] BP_Gako_C actor not found\n")
        return
    end

    local okName, fullName = pcall(function() return GakoActor:GetFullName() end)
    print(string.format("[FrogFlagReader] BP_Gako_C: %s\n", okName and fullName or "?"))

    local okBefore, before = pcall(function() return GakoActor.Gako_Life end)
    print(string.format("[FrogFlagReader] Gako_Life BEFORE = %s\n", tostring(okBefore and before or "?")))

    if not okBefore or type(before) ~= "number" then
        print("[FrogFlagReader] Could not read Gako_Life as a number, aborting write test\n")
        return
    end

    local newValue = before - 1
    local okSet, setErr = pcall(function() GakoActor:SetPropertyValue("Gako_Life", newValue) end)
    print(string.format("[FrogFlagReader] SetPropertyValue(Gako_Life, %s) ok=%s err=%s\n",
        tostring(newValue), tostring(okSet), tostring(setErr)))

    local okAfter, after = pcall(function() return GakoActor.Gako_Life end)
    print(string.format("[FrogFlagReader] Gako_Life AFTER = %s\n", tostring(okAfter and after or "?")))

    -- Restore the original value so this probe doesn't leave a lasting change.
    local okRestoreCall = pcall(function() GakoActor:SetPropertyValue("Gako_Life", before) end)
    local okRestored, restored = pcall(function() return GakoActor.Gako_Life end)
    print(string.format("[FrogFlagReader] Gako_Life RESTORED (call ok=%s) = %s\n",
        tostring(okRestoreCall), tostring(okRestored and restored or "?")))
end

-- IPC feasibility probe for milestone 4: can this Lua environment write a
-- plain file at all? If so, file-polling is a viable bridge between the
-- external Python client and this in-game script (no sockets needed).
local function TestFileIO()
    local okOpen, fileOrErr = pcall(function()
        return io.open("FrogFlagReaderMod_iotest.txt", "w")
    end)
    if not okOpen or not fileOrErr then
        print(string.format("[FrogFlagReader] io.open FAILED: open_ok=%s result=%s\n",
            tostring(okOpen), tostring(fileOrErr)))
        return
    end

    local file = fileOrErr
    local okWrite, writeErr = pcall(function()
        file:write("hello from lua\n")
        file:close()
    end)
    print(string.format("[FrogFlagReader] io.open/write ok=%s err=%s\n",
        tostring(okWrite), tostring(writeErr)))
end

RegisterKeyBind(Key.NUM_FIVE, {ModifierKey.CONTROL}, TestFileIO)
ExecuteWithDelay(6000, TestFileIO)

-- Diagnostic for why the bridge mod's FindAllOf("GakoComponent") isn't
-- finding an uncollected duck: list every live instance and its bColleted
-- state directly, rather than guessing. Turned out to be level streaming --
-- FindAllOf only returns whatever's currently loaded near the player, see
-- the milestone 4 NOTES.md entry.
local function DumpGakoComponents()
    local components = FindAllOf("GakoComponent")
    if not components then
        print("[FrogFlagReader] FindAllOf(GakoComponent) returned nothing\n")
        return
    end
    print(string.format("[FrogFlagReader] Found %d GakoComponent instance(s)\n", #components))
    for i, component in ipairs(components) do
        local okName, name = pcall(function() return component:GetFullName() end)
        local okCollected, collected = pcall(function() return component.bColleted end)
        print(string.format("[FrogFlagReader]   [%d] %s bColleted=%s (ok=%s)\n",
            i, okName and name or "?", tostring(collected), tostring(okCollected)))
    end
end

RegisterKeyBind(Key.NUM_FOUR, {ModifierKey.CONTROL}, DumpGakoComponents)

-- bColleted is permanent across sessions (same trap as the duck-count
-- tracker) so after a long playthrough almost everything nearby already
-- reads true, and waiting to stumble on a genuinely uncollected duck isn't
-- reliable. Instead, force whichever GakoComponent is currently loaded
-- back to bColleted=false ourselves, purely as test setup, so the
-- unlock_duck command path can be exercised deterministically.
local function ForceUncollectNearbyGako()
    local components = FindAllOf("GakoComponent")
    if not components or #components == 0 then
        print("[FrogFlagReader] ForceUncollectNearbyGako: no GakoComponent currently loaded\n")
        return
    end
    local component = components[1]
    local okName, name = pcall(function() return component:GetFullName() end)
    local okSet, setErr = pcall(function() component:SetPropertyValue("bColleted", false) end)
    local okCheck, after = pcall(function() return component.bColleted end)
    print(string.format(
        "[FrogFlagReader] ForceUncollectNearbyGako on %s SetPropertyValue ok=%s err=%s bColleted(after)=%s\n",
        okName and name or "?", tostring(okSet), tostring(setErr), tostring(okCheck and after or "?")))
end

RegisterKeyBind(Key.NUM_THREE, {ModifierKey.CONTROL}, ForceUncollectNearbyGako)

-- Ground truth instead of guessing from static function names: hook every
-- plausible "duck got hit/shot" candidate and log which ones actually
-- fire, on what object, when a real duck gets shot in gameplay. The
-- persistent unlock counter can't tell us this since it's a one-shot
-- (already-collected ducks never change), per-run reflection is our best
-- source of truth here.
local function LogHook(FunctionPath)
    RegisterHook(FunctionPath, function(self, ...)
        local ok, name = pcall(function() return self:GetFullName() end)
        print(string.format("[FrogFlagReader] HOOK FIRED: %s on %s\n", FunctionPath, ok and name or "?"))
    end)
end

LogHook("/Script/MGS3.GakoComponent:GakoDefenseCallback")
LogHook("/Script/MGS3.GakoComponent:SetGakoEnemyNoise")
LogHook("/Game/Blueprints/Gako/BP_Gako.BP_Gako_C:OnHit")
LogHook("/Game/Blueprints/Gako/BP_Gako.BP_Gako_C:GakoHitSoundAndVFX")

-- GakoSetCollected specifically: log synchronously at call time only --
-- no delayed/async access to `self` afterward. An earlier version of this
-- probe held onto `self` across an ExecuteWithDelay and crashed the game,
-- likely a use-after-free if the duck actor gets destroyed shortly after
-- collection. For the "after" state, use the safe Ctrl+Num4
-- (DumpGakoComponents) keybind instead, which does a fresh FindAllOf
-- query rather than holding a stale reference across time.
RegisterHook("/Script/MGS3.GakoComponent:GakoSetCollected", function(self, ...)
    -- `self` is a RemoteUnrealParam-style wrapper, not a plain UObject --
    -- confirmed by testing: direct self:GetFullName()/self.bColleted give
    -- nil/garbage, but self:get() unwraps to a real object where every
    -- method/property access agrees. Always use the unwrapped object.
    local okGet, unwrapped = pcall(function() return self:get() end)
    if not okGet or not unwrapped then
        print(string.format("[FrogFlagReader] GakoSetCollected: self:get() failed: %s\n", tostring(unwrapped)))
        return
    end

    local okName, name = pcall(function() return unwrapped:GetFullName() end)
    local okBefore, before = pcall(function() return unwrapped.bColleted end)
    local okClass, className = pcall(function() return unwrapped:GetClass():GetFullName() end)
    print(string.format(
        "[FrogFlagReader] GakoSetCollected FIRING on %s (class=%s) bColleted(pre-call)=%s\n",
        okName and name or "?",
        okClass and className or "?",
        tostring(okBefore and before or "?")))
end)

-- Manual triggers:
--   Ctrl+Num9: read known counters
--   Ctrl+Num8: dump every function/property on the subsystem's full class hierarchy
--   Ctrl+Num7: milestone 3 write test v1 (GakoSetCollected on a live duck -- one-shot, kept for reference)
--   Ctrl+Num6: milestone 3 write test v2 (Gako_Life decrement/restore -- repeatable)
--   Ctrl+Num5: file I/O feasibility probe
--   Ctrl+Num4: dump every live GakoComponent + its bColleted state
--   Ctrl+Num3: force whichever GakoComponent is loaded back to bColleted=false (test setup only)
RegisterKeyBind(Key.NUM_NINE, {ModifierKey.CONTROL}, ReadKerotanStatus)
RegisterKeyBind(Key.NUM_EIGHT, {ModifierKey.CONTROL}, DumpKerotanSubsystemMembers)
RegisterKeyBind(Key.NUM_SEVEN, {ModifierKey.CONTROL}, TestGakoWrite)
RegisterKeyBind(Key.NUM_SIX, {ModifierKey.CONTROL}, TestGakoLifeWrite)

-- Also try automatically a few seconds after the mod loads, in case the
-- game is already in a gameplay session. TestGakoWrite is NOT auto-run --
-- it has a real, permanent side effect on the save, so it only runs on the
-- explicit Ctrl+Num7 keybind.
ExecuteWithDelay(5000, ReadKerotanStatus)
ExecuteWithDelay(5500, DumpKerotanSubsystemMembers)
