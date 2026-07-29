-- Recon script for mgsdelta-connector milestone 2 ("read one flag").
-- Reads the live BP_KerotanSubsystem_C GameInstanceSubsystem and prints its
-- frog/gako unlock counters to UE4SS.log. Not part of any real mod, just a
-- throwaway probe for this session.

local UEHelpers = require("UEHelpers")

-- Generic, type-aware property value dumper -- adapted from
-- ConsoleCommandsMod/Scripts/dump_object.lua's DumpPropertyWithinObject,
-- since struct/map property values don't behave like plain Lua tables
-- (pairs()/ForEach don't apply uniformly) and this file already has the
-- correct type-by-type handling worked out.
local function FormatPropertyValue(Object, Property)
    local okFName, fName = pcall(function() return Property:GetFName():ToString() end)
    if not okFName then return "?" end

    local ok, result = pcall(function()
        if Property:IsA(PropertyTypes.StructProperty) then
            local Value = Object[fName]
            local parts = {}
            local StructType = Property:GetStruct()
            StructType:ForEachProperty(function(SubProperty)
                local subName = SubProperty:GetFName():ToString()
                table.insert(parts, string.format("%s=%s", subName, FormatPropertyValue(Value, SubProperty)))
            end)
            return "{" .. table.concat(parts, ", ") .. "}"
        elseif Property:IsA(PropertyTypes.MapProperty) then
            return "<map, use TMap:ForEach directly>"
        elseif Property:IsA(PropertyTypes.ArrayProperty) then
            local Value = Object[fName]
            return string.format("<array, %d elements>", Value:GetArrayNum())
        elseif Property:IsA(PropertyTypes.ObjectProperty) then
            local Value = Object[fName]
            if not Value or not Value:IsValid() then return "nil" end
            return Value:GetFullName()
        elseif Property:IsA(PropertyTypes.BoolProperty) then
            return tostring(Object[fName])
        elseif Property:IsA(PropertyTypes.EnumProperty) then
            local Value = Object[fName]
            return string.format("%s(%s)", Property:GetEnum():GetNameByValue(Value):ToString(), tostring(Value))
        else
            return tostring(Object[fName])
        end
    end)
    return ok and result or string.format("<error: %s>", tostring(result))
end

-- A struct VALUE (e.g. weapon.m_gunData) is not a UObject and does not
-- support :GetClass() -- confirmed live, calling it crashed the game.
-- The correct struct TYPE only comes from the DECLARING property's
-- :GetStruct(), same as FormatPropertyValue's own recursive struct case.
-- So this takes the parent object + the field name and finds the
-- declaring property itself, rather than trying to introspect the value.
local function DumpStructField(label, ParentObject, FieldName)
    if not ParentObject or not ParentObject:IsValid() then
        print(string.format("[FrogFlagReader] %s: parent object invalid\n", label))
        return
    end
    local okClass, ParentClass = pcall(function() return ParentObject:GetClass() end)
    if not okClass or not ParentClass then
        print(string.format("[FrogFlagReader] %s: could not resolve parent class\n", label))
        return
    end

    local FieldProperty = nil
    local Depth = 0
    local Class = ParentClass
    while Class and Class:IsValid() and Depth < 12 and not FieldProperty do
        Class:ForEachProperty(function(Property)
            local okName, name = pcall(function() return Property:GetFName():ToString() end)
            if okName and name == FieldName then
                FieldProperty = Property
            end
        end)
        Class = Class:GetSuperStruct()
        Depth = Depth + 1
    end

    if not FieldProperty then
        print(string.format("[FrogFlagReader] %s: property '%s' not found\n", label, FieldName))
        return
    end

    local okValue, Value = pcall(function() return ParentObject[FieldName] end)
    if not okValue or not Value then
        print(string.format("[FrogFlagReader] %s: field read failed\n", label))
        return
    end

    local okStruct, StructType = pcall(function() return FieldProperty:GetStruct() end)
    if not okStruct or not StructType then
        print(string.format("[FrogFlagReader] %s: not a struct property (or GetStruct failed)\n", label))
        return
    end

    print(string.format("[FrogFlagReader] %s:\n", label))
    local okForEach, err = pcall(function()
        StructType:ForEachProperty(function(SubProperty)
            local okName, name = pcall(function() return SubProperty:GetFName():ToString() end)
            print(string.format("[FrogFlagReader]   %s = %s\n",
                okName and name or "?", FormatPropertyValue(Value, SubProperty)))
        end)
    end)
    if not okForEach then
        print(string.format("[FrogFlagReader] %s: ForEachProperty failed: %s\n", label, tostring(err)))
    end
end

-- Fun side probe: find the player pawn and dump anything ammo/weapon/
-- inventory-related on its full class hierarchy, so we know what property
-- (or component) to use for a "shoot a duck, get ammo" reward hook. No
-- direct "ammo" property was found on the pawn itself -- widen the filter
-- and also print every Blueprint-level (shallow) property/function
-- unfiltered, since a weapon/inventory component reference is more likely
-- named like "WeaponComponent_GEN_VARIABLE" than to mention ammo directly.
local function DumpPlayerAmmoProperties()
    local Player = UEHelpers.GetPlayer()
    if not Player or not Player:IsValid() then
        print("[FrogFlagReader] DumpPlayerAmmoProperties: no valid player pawn found\n")
        return
    end

    local okName, name = pcall(function() return Player:GetFullName() end)
    print(string.format("[FrogFlagReader] Player pawn: %s\n", okName and name or "?"))

    local Class = Player:GetClass()
    local Depth = 0
    while Class and Class:IsValid() and Depth < 12 do
        local okCName, cName = pcall(function() return Class:GetFullName() end)
        local isShallow = Depth < 2
        Class:ForEachProperty(function(Property)
            local okPName, pName = pcall(function() return Property:GetFullName() end)
            if not okPName then return end
            local lower = pName:lower()
            if isShallow or lower:find("ammo") or lower:find("weapon") or lower:find("inventory") then
                print(string.format("[FrogFlagReader]   [%s] Property: %s\n", okCName and cName or "?", pName))
            end
        end)
        if isShallow then
            Class:ForEachFunction(function(Function)
                local okFName, fName = pcall(function() return Function:GetFullName() end)
                local lower = okFName and fName:lower() or ""
                if lower:find("ammo") or lower:find("weapon") or lower:find("shoot") or lower:find("fire") then
                    print(string.format("[FrogFlagReader]   [%s] Function: %s\n", okCName and cName or "?", okFName and fName or "?"))
                end
            end)
        end
        Class = Class:GetSuperStruct()
        Depth = Depth + 1
    end
end

-- No "ammo" property lives directly on the pawn -- the strongest
-- candidates found were GsrPlayer:m_equipController and :ItemController,
-- likely sub-objects managing the equipped weapon / general inventory.
-- Drill into each and dump ITS properties/functions for ammo-related
-- content, since that's probably where the real ammo count lives.
local function DumpPlayerSubControllers()
    local Player = UEHelpers.GetPlayer()
    if not Player or not Player:IsValid() then
        print("[FrogFlagReader] DumpPlayerSubControllers: no valid player pawn found\n")
        return
    end

    local function DumpObject(label, obj)
        if not obj or not obj:IsValid() then
            print(string.format("[FrogFlagReader] %s: nil/invalid\n", label))
            return
        end
        local okName, name = pcall(function() return obj:GetFullName() end)
        print(string.format("[FrogFlagReader] %s: %s\n", label, okName and name or "?"))

        local Class = obj:GetClass()
        local Depth = 0
        while Class and Class:IsValid() and Depth < 6 do
            local okCName, cName = pcall(function() return Class:GetFullName() end)
            Class:ForEachProperty(function(Property)
                local okPName, pName = pcall(function() return Property:GetFullName() end)
                if okPName then
                    print(string.format("[FrogFlagReader]   [%s] Property: %s\n", okCName and cName or "?", pName))
                end
            end)
            Class:ForEachFunction(function(Function)
                local okFName, fName = pcall(function() return Function:GetFullName() end)
                if okFName then
                    print(string.format("[FrogFlagReader]   [%s] Function: %s\n", okCName and cName or "?", fName))
                end
            end)
            Class = Class:GetSuperStruct()
            Depth = Depth + 1
        end
    end

    local okEquip, equipController = pcall(function() return Player.m_equipController end)
    DumpObject("m_equipController", okEquip and equipController or nil)

    local okItem, itemController = pcall(function() return Player.ItemController end)
    DumpObject("ItemController", okItem and itemController or nil)

    -- GetCurrentWeapon() returns the actual equipped weapon actor -- the
    -- pistol's real ammo (62, per live play) doesn't appear in
    -- m_weaponStockedAmmo at all, so it's more likely stored directly on
    -- the weapon actor itself (matching how the community trainer's
    -- WeaponsTable tracks per-weapon CurrentAmmo/Clip directly, not
    -- through a shared map).
    if okEquip and equipController and equipController:IsValid() then
        local okWeapon, weapon = pcall(function() return equipController:GetCurrentWeapon() end)
        DumpObject("GetCurrentWeapon()", okWeapon and weapon or nil)

        -- Get/SetLoadedAmmoCount don't stick -- m_gunData (a StructProperty
        -- on the weapon actor) might be the real underlying data they
        -- fail to sync back to. Dump its actual fields directly.
        if okWeapon and weapon and weapon:IsValid() then
            DumpStructField("m_gunData", weapon, "m_gunData")

            -- m_gunData turned out to be static weapon config (VFX/mesh/
            -- bullet class), not ammo. GunPartsController (an
            -- ObjectProperty on the weapon, not yet explored) is the next
            -- candidate for holding real, mutable ammo/parts state.
            local okParts, partsController = pcall(function() return weapon.GunPartsController end)
            DumpObject("GunPartsController", okParts and partsController or nil)
        end
    end
end

-- SetCurrentStockedAmmoCount's write doesn't stick (confirmed live: value
-- changes momentarily but the player's actual ammo is unaffected) -- it's
-- likely a transient/cached accessor, re-synced from the real per-weapon
-- store. Dump m_weaponStockedAmmo (a MapProperty) and the current weapon
-- slot/id fields directly to find the real, persistent value to write.
local function DumpWeaponStockedAmmoMap()
    local Player = UEHelpers.GetPlayer()
    if not Player or not Player:IsValid() then
        print("[FrogFlagReader] DumpWeaponStockedAmmoMap: no valid player pawn found\n")
        return
    end
    local okEquip, equipController = pcall(function() return Player.m_equipController end)
    if not okEquip or not equipController or not equipController:IsValid() then
        print("[FrogFlagReader] DumpWeaponStockedAmmoMap: m_equipController invalid\n")
        return
    end

    local okSlot, slot = pcall(function() return equipController.m_waponSlotForAmmo end)
    print(string.format("[FrogFlagReader] m_waponSlotForAmmo = %s\n", tostring(okSlot and slot or "?")))

    local okPrevId, prevId = pcall(function() return equipController.m_previousWeaponIdForAmmo end)
    print(string.format("[FrogFlagReader] m_previousWeaponIdForAmmo = %s\n", tostring(okPrevId and prevId or "?")))

    local okMap, map = pcall(function() return equipController.m_weaponStockedAmmo end)
    if not okMap or not map then
        print(string.format("[FrogFlagReader] m_weaponStockedAmmo read failed: %s\n", tostring(map)))
        return
    end
    -- TMap:ForEach's key/value are RemoteUnrealParam wrappers -- same
    -- pattern as RegisterHook's `self` -- need :get() to unwrap before use.
    local okIter, iterErr = pcall(function()
        map:ForEach(function(key, value)
            local okKey, keyVal = pcall(function() return key:get() end)
            local okVal, valVal = pcall(function() return value:get() end)
            print(string.format("[FrogFlagReader]   m_weaponStockedAmmo[%s] = %s\n",
                tostring(okKey and keyVal or "?"), tostring(okVal and valVal or "?")))
        end)
    end)
    if not okIter then
        print(string.format("[FrogFlagReader] m_weaponStockedAmmo iteration failed: %s\n", tostring(iterErr)))
    end
end

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

    -- Field mapping fixed via UE4SS Live View reflection dump: each
    -- function's ReturnValue StructProperty's [ss: ...] address confirms
    -- the REAL return struct type, which was backwards from what this probe
    -- originally assumed (see research/NOTES.md milestone 5):
    --   GetCurrentMapKerotanStatus -> KerotanStatus (position/Rotation/bIsUnlocked/bHasKerotan)
    --   GetKerotanUnlockStatus -> KerotanGakoUnlockStatus (UnlockCount/TotalCount/...), same aggregate shape as GetGakoUnlockStatus
    local ok2, MapStatus = pcall(function() return KerotanSubsystem:GetCurrentMapKerotanStatus() end)
    if ok2 and MapStatus then
        print(string.format("[FrogFlagReader] GetCurrentMapKerotanStatus -> bIsUnlocked=%s bHasKerotan=%s\n",
            tostring(MapStatus.bIsUnlocked), tostring(MapStatus.bHasKerotan)))
    else
        print(string.format("[FrogFlagReader] GetCurrentMapKerotanStatus call failed: %s\n", tostring(MapStatus)))
    end

    local ok3, KerotanStatus = pcall(function() return KerotanSubsystem:GetKerotanUnlockStatus() end)
    if ok3 and KerotanStatus then
        print(string.format("[FrogFlagReader] GetKerotanUnlockStatus -> UnlockCount=%s TotalCount=%s IsExistInCurrentArea=%s IsUnlcokedInCurrentArea=%s\n",
            tostring(KerotanStatus.UnlockCount), tostring(KerotanStatus.TotalCount),
            tostring(KerotanStatus.IsExistInCurrentArea), tostring(KerotanStatus.IsUnlcokedInCurrentArea)))
    else
        print(string.format("[FrogFlagReader] GetKerotanUnlockStatus call failed: %s\n", tostring(KerotanStatus)))
    end
end

-- Milestone 5 probe: GetKerotanUnlockStatus/GetCurrentMapKerotanStatus
-- returned all-nil fields when called with no args (see NOTES.md milestone
-- 2) -- maybe they actually take a parameter (a frog index/reference) we
-- never supplied. A UFunction is itself a UStruct whose properties ARE its
-- parameters (inputs and the return value), so dumping those tells us the
-- real signature instead of guessing.
local function DumpFunctionParams(FunctionFullName)
    local KerotanSubsystem = FindFirstOf("BP_KerotanSubsystem_C")
    if not KerotanSubsystem or not KerotanSubsystem:IsValid() then
        print("[FrogFlagReader] DumpFunctionParams: BP_KerotanSubsystem_C not found\n")
        return
    end
    local Class = KerotanSubsystem:GetClass()
    local Depth = 0
    while Class and Class:IsValid() and Depth < 10 do
        Class:ForEachFunction(function(Function)
            local okName, name = pcall(function() return Function:GetFullName() end)
            if okName and name == FunctionFullName then
                print(string.format("[FrogFlagReader] Params for %s:\n", name))
                -- Function, like a hook's `self`, may be a wrapper needing
                -- :get() before further method calls work -- and the whole
                -- ForEachProperty call itself needs to be pcall'd, since a
                -- nullptr-instance error here isn't a plain Lua error the
                -- inner pcalls alone would catch.
                local okGet, unwrapped = pcall(function() return Function:get() end)
                local target = (okGet and unwrapped) or Function
                local okForEach, err = pcall(function()
                    target:ForEachProperty(function(Property)
                        local okPName, pName = pcall(function() return Property:GetFullName() end)
                        print(string.format("[FrogFlagReader]   Param: %s\n", okPName and pName or "?"))
                    end)
                end)
                if not okForEach then
                    print(string.format("[FrogFlagReader]   ForEachProperty failed: %s\n", tostring(err)))
                end
            end
        end)
        Class = Class:GetSuperStruct()
        Depth = Depth + 1
    end
end

-- By symmetry with GakoComponent (the per-duck component): if frogs have
-- their own per-instance "KerotanComponent", FindAllOf should surface it
-- exactly like it did for ducks, without needing to find a working
-- subsystem-level aggregate call at all.
local function DumpKerotanComponents()
    local components = FindAllOf("KerotanComponent")
    if not components or #components == 0 then
        print("[FrogFlagReader] FindAllOf(KerotanComponent) returned nothing\n")
        return
    end
    print(string.format("[FrogFlagReader] Found %d KerotanComponent instance(s)\n", #components))
    for i, component in ipairs(components) do
        local okName, name = pcall(function() return component:GetFullName() end)
        print(string.format("[FrogFlagReader]   [%d] %s\n", i, okName and name or "?"))
        local Class = component:GetClass()
        local Depth = 0
        while Class and Class:IsValid() and Depth < 3 do
            Class:ForEachProperty(function(Property)
                local okPName, pName = pcall(function() return Property:GetFullName() end)
                print(string.format("[FrogFlagReader]     Property: %s\n", okPName and pName or "?"))
            end)
            Class = Class:GetSuperStruct()
            Depth = Depth + 1
        end
    end
end

-- No separate "KerotanComponent" class exists at all (confirmed empty
-- FindAllOf above), unlike ducks. Try the more direct parallel to how
-- Gako_Life/bColleted were found on ducks: look at the frog ACTOR itself
-- (BP_Kerotan_C, guessing the same naming convention as BP_Gako_C) and
-- dump its own properties directly, rather than assuming a component.
local function DumpKerotanActors()
    local actors = FindAllOf("BP_Kerotan_C")
    if not actors or #actors == 0 then
        print("[FrogFlagReader] FindAllOf(BP_Kerotan_C) returned nothing\n")
        return
    end
    print(string.format("[FrogFlagReader] Found %d BP_Kerotan_C instance(s)\n", #actors))
    for i, actor in ipairs(actors) do
        local okName, name = pcall(function() return actor:GetFullName() end)
        print(string.format("[FrogFlagReader]   [%d] %s\n", i, okName and name or "?"))
        local Class = actor:GetClass()
        local Depth = 0
        while Class and Class:IsValid() and Depth < 3 do
            local okCName, cName = pcall(function() return Class:GetFullName() end)
            print(string.format("[FrogFlagReader]     -- class %s --\n", okCName and cName or "?"))
            Class:ForEachProperty(function(Property)
                local okPName, pName = pcall(function() return Property:GetFullName() end)
                print(string.format("[FrogFlagReader]     Property: %s\n", okPName and pName or "?"))
            end)
            Class = Class:GetSuperStruct()
            Depth = Depth + 1
        end
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
-- state directly, rather than guessing.
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

-- Historical note: milestone 4 needed to discover which function fires
-- when a duck gets shot, since the persistent unlock counter/flag can't
-- reveal that (one-shot, already-collected ducks never change). That was
-- answered (GakoSetCollected -- see below) via a LogHook helper that hooked
-- every plausible candidate (GakoDefenseCallback, SetGakoEnemyNoise, OnHit,
-- GakoHitSoundAndVFX) and logged which ones actually fired. Removed now
-- that the answer's known -- every extra hook here is one more native hook
-- re-registered on every mod restart, and repeated restarts across a long
-- session already caused real accumulated-hook-stacking crashes (see
-- research/NOTES.md). Keep the fewest live hooks needed.

-- GakoSetCollected specifically: log synchronously at call time only --
-- no delayed/async access to `self` afterward. An earlier version of this
-- probe held onto `self` across an ExecuteWithDelay and crashed the game,
-- likely a use-after-free if the duck actor gets destroyed shortly after
-- collection. For the "after" state, use the safe Ctrl+Num4
-- (DumpGakoComponents) keybind instead, which does a fresh FindAllOf
-- query rather than holding a stale reference across time.
local okRegister, registerErr = pcall(function()
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

        -- Fun reward: bump loaded ammo whenever a duck gets collected.
        -- GetCurrentStockedAmmoCount/SetCurrentStockedAmmoCount (Ctrl+O) is
        -- a stale/cached accessor (writes never stick). Directly mutating
        -- m_weaponStockedAmmo (a TMap) also didn't reflect the real
        -- equipped weapon's ammo (the pistol never appeared in it) and
        -- risks crashing since combat code actively uses that map.
        -- GetCurrentWeapon() returns the actual weapon actor (GsrGun
        -- class), which has its own GetLoadedAmmoCount/SetLoadedAmmoCount
        -- -- simpler, no map, and the loaded/clip count is directly
        -- visible on the HUD.
        local okReward = pcall(function()
            local Player = UEHelpers.GetPlayer()
            if not Player or not Player:IsValid() then
                print("[FrogFlagReader] Ammo reward: no valid player pawn\n")
                return
            end
            local EquipController = Player.m_equipController
            if not EquipController or not EquipController:IsValid() then
                print("[FrogFlagReader] Ammo reward: m_equipController invalid\n")
                return
            end
            local okWeapon, weapon = pcall(function() return EquipController:GetCurrentWeapon() end)
            if not okWeapon or not weapon or not weapon:IsValid() then
                print("[FrogFlagReader] Ammo reward: GetCurrentWeapon() invalid\n")
                return
            end

            local okBefore, before = pcall(function() return weapon:GetLoadedAmmoCount() end)
            if not okBefore then
                print(string.format("[FrogFlagReader] Ammo reward: GetLoadedAmmoCount failed: %s\n", tostring(before)))
                return
            end

            -- SetLoadedAmmoCount reported success and read back correctly,
            -- but never showed up in the real HUD/gameplay (confirmed
            -- live). Trying ReduceLoadedAmmoCount(-10) instead -- a raw
            -- Set might skip whatever normally notifies the UI to
            -- refresh, whereas a "Reduce" function (the kind normally
            -- called when firing/reloading) more likely triggers it too.
            local okReduce, reduceErr = pcall(function() weapon:ReduceLoadedAmmoCount(-10) end)
            print(string.format("[FrogFlagReader] Ammo reward: ReduceLoadedAmmoCount(-10) ok=%s err=%s\n",
                tostring(okReduce), tostring(reduceErr)))

            local okAfter, after = pcall(function() return weapon:GetLoadedAmmoCount() end)
            print(string.format("[FrogFlagReader] Ammo reward: %s -> readback=%s\n",
                tostring(before), tostring(okAfter and after or "?")))
        end)
        if not okReward then
            print("[FrogFlagReader] Ammo reward failed (see next line if any)\n")
        end
    end)
end)
if not okRegister then
    print(string.format("[FrogFlagReader] RegisterHook failed for GakoSetCollected: %s\n", tostring(registerErr)))
end

local function DumpKerotanFunctionParams()
    DumpFunctionParams("Function /Script/MGS3.KerotanSubsystem:GetKerotanUnlockStatus")
    DumpFunctionParams("Function /Script/MGS3.KerotanSubsystem:GetCurrentMapKerotanStatus")
    DumpFunctionParams("Function /Script/MGS3.KerotanSubsystem:GetGakoUnlockStatus")
end

-- CXXHeaderDump (Ctrl+H) revealed the game's own internal QA debug-menu
-- cheat functions: UGsrPlayerDebugMenuState (a UObject, subclassed as
-- BP_PlayerDebugMenuState_C) has OnExecuteFullAmmo/OnExecuteSetStockedAmmo/
-- OnExecuteGetAllWeaponItem/OnExecuteChangeItem -- literally the dev cheat
-- menu callbacks, which write through the real authoritative ammo/item
-- state (unlike every SetXxxAmmoCount we've tried, which silently no-ops).
-- AIcsCharacter (AGsrPlayer's base) holds a `DebugMenuState` UObject*
-- property directly, and UIcsDebugMenuDaemon is a UGameInstanceSubsystem
-- (auto-created every session, shipping build or not). This probe is
-- READ-ONLY -- it only checks whether these are already populated live,
-- it does not call any OnExecute* function yet.
local function ProbeDebugMenuState()
    local player = UEHelpers.GetPlayer()
    if not player or not player:IsValid() then
        print("[FrogFlagReader] ProbeDebugMenuState: no player pawn\n")
        return
    end

    local okState, state = pcall(function() return player.DebugMenuState end)
    if okState and state and state:IsValid() then
        local okClass, className = pcall(function() return state:GetClass():GetFullName() end)
        print(string.format("[FrogFlagReader] player.DebugMenuState is VALID, class=%s\n",
            okClass and className or "?"))
    else
        print(string.format("[FrogFlagReader] player.DebugMenuState: ok=%s valid=%s\n",
            tostring(okState), tostring(state and state:IsValid())))
    end

    local daemon = FindFirstOf("IcsDebugMenuDaemon")
    if daemon and daemon:IsValid() then
        print("[FrogFlagReader] IcsDebugMenuDaemon found, valid=true\n")
        local okSys, system = pcall(function() return daemon:GetDebugMenuSystem() end)
        if okSys and system and system:IsValid() then
            local okClass, className = pcall(function() return system:GetClass():GetFullName() end)
            print(string.format("[FrogFlagReader] GetDebugMenuSystem() -> VALID, class=%s\n",
                okClass and className or "?"))
        else
            print(string.format("[FrogFlagReader] GetDebugMenuSystem(): ok=%s valid=%s\n",
                tostring(okSys), tostring(system and system:IsValid())))
        end
    else
        print("[FrogFlagReader] IcsDebugMenuDaemon: not found\n")
    end
end

-- OnExecuteFullAmmo crashed the engine 3x at the same point regardless of
-- args passed (nil vs a real constructed UIcsDebugMenuValue) -- we can't
-- see the BP graph body (CXXHeaderDump is signatures only), so we can't
-- diagnose what internal state it still needs. Pivoting: UGsrEquipController
-- (found in the same Ctrl+H dump) has SetStockedAmmoCount(EquipId, Count)/
-- ReduceLoadedAmmoCount(EquipId) -- called on the player's REAL, already-
-- running m_equipController, not a freshly constructed orphan object, so
-- none of the "missing wiring" risk applies. (Our old ReduceLoadedAmmoCount
-- crash was on the wrong object entirely -- AGsrGun doesn't even have that
-- function -- and with the wrong arg type, a delta instead of an
-- EGsrEquipId enum.)
local function TryEquipControllerAmmoWrite()
    local player = UEHelpers.GetPlayer()
    if not player or not player:IsValid() then
        print("[FrogFlagReader] TryEquipControllerAmmoWrite: no player pawn\n")
        return
    end
    local okEquip, equip = pcall(function() return player.m_equipController end)
    if not okEquip or not equip or not equip:IsValid() then
        print(string.format("[FrogFlagReader] player.m_equipController: ok=%s valid=%s\n",
            tostring(okEquip), tostring(equip and equip:IsValid())))
        return
    end

    local okId, weaponId = pcall(function() return equip:GetCurrentWeaponId() end)
    local okSlot, slot = pcall(function() return equip:GetCurrentWeaponSlot() end)
    print(string.format("[FrogFlagReader] weaponId ok=%s value=%s, slot ok=%s value=%s\n",
        tostring(okId), tostring(weaponId), tostring(okSlot), tostring(slot)))
    if not okId or not okSlot then
        return
    end

    local okStockedBefore, stockedBefore = pcall(function() return equip:GetStockedAmmoCount(slot) end)
    local okLoadedBefore, loadedBefore = pcall(function() return equip:GetLoadedAmmoCount(slot) end)
    print(string.format("[FrogFlagReader] Before: Stocked ok=%s value=%s, Loaded ok=%s value=%s\n",
        tostring(okStockedBefore), tostring(stockedBefore), tostring(okLoadedBefore), tostring(loadedBefore)))

    local okSet, setErr = pcall(function() equip:SetStockedAmmoCount(weaponId, 999) end)
    print(string.format("[FrogFlagReader] SetStockedAmmoCount(weaponId, 999) ok=%s err=%s\n",
        tostring(okSet), tostring(setErr)))

    local okStockedAfter, stockedAfter = pcall(function() return equip:GetStockedAmmoCount(slot) end)
    print(string.format("[FrogFlagReader] After: Stocked ok=%s value=%s (check in-game HUD too!)\n",
        tostring(okStockedAfter), tostring(stockedAfter)))
end

-- Read-only companion to Ctrl+U -- does NOT call SetStockedAmmoCount, just
-- reports the current values. Use this after Ctrl+U followed by switching
-- weapons away and back in-game, to test whether the write actually landed
-- in the real per-weapon map but only becomes visible on a weapon-switch
-- refresh (a pattern seen elsewhere in this game's caches).
local function ReadEquipControllerAmmo()
    local player = UEHelpers.GetPlayer()
    if not player or not player:IsValid() then
        print("[FrogFlagReader] ReadEquipControllerAmmo: no player pawn\n")
        return
    end
    local okEquip, equip = pcall(function() return player.m_equipController end)
    if not okEquip or not equip or not equip:IsValid() then
        print(string.format("[FrogFlagReader] player.m_equipController: ok=%s valid=%s\n",
            tostring(okEquip), tostring(equip and equip:IsValid())))
        return
    end
    local okId, weaponId = pcall(function() return equip:GetCurrentWeaponId() end)
    local okSlot, slot = pcall(function() return equip:GetCurrentWeaponSlot() end)
    local okStocked, stocked = pcall(function() return equip:GetStockedAmmoCount(slot) end)
    local okLoaded, loaded = pcall(function() return equip:GetLoadedAmmoCount(slot) end)
    print(string.format("[FrogFlagReader] Read-only: weaponId=%s slot=%s Stocked ok=%s value=%s, Loaded ok=%s value=%s\n",
        tostring(okId and weaponId), tostring(okSlot and slot),
        tostring(okStocked), tostring(stocked), tostring(okLoaded), tostring(loaded)))
end

-- player.DebugMenuState came back invalid (Ctrl+L) -- the game never
-- lazily creates it since no debug UI has ever been opened this session.
-- But UIcsDebugMenuStateContainer::CreateIcsDebugMenuState and the plain
-- StaticConstructObject primitive (Docs/lua-api/global-functions/
-- staticconstructobject.md) mean we can construct our OWN instance of
-- BP_PlayerDebugMenuState_C directly, then call its OnExecute* cheat
-- functions (OnExecuteFullAmmo etc, found via the Ctrl+H SDK dump) without
-- ever needing the real debug menu UI/widget system involved at all.
-- Kept as two separate steps (construct here, fire the cheat on a
-- different keybind) so a crash in step 2 doesn't retrigger step 1's
-- object construction too.
local G_DebugMenuStateInstance = nil

local function TryConstructPlayerDebugMenu()
    local player = UEHelpers.GetPlayer()
    if not player or not player:IsValid() then
        print("[FrogFlagReader] TryConstructPlayerDebugMenu: no player pawn\n")
        return
    end

    -- AIcsCharacter (AGsrPlayer's base) holds `DebugMenuStateClass`
    -- (TSubclassOf<UIcsActorDebugMenuState>) right next to the
    -- (currently-null) `DebugMenuState` instance pointer -- this is the
    -- engine's own class reference, so read it directly instead of
    -- guessing the Blueprint's package path for StaticFindObject.
    local okClass, class = pcall(function() return player.DebugMenuStateClass end)
    if not okClass or not class or not class:IsValid() then
        print(string.format("[FrogFlagReader] player.DebugMenuStateClass: ok=%s valid=%s\n",
            tostring(okClass), tostring(class and class:IsValid())))
        return
    end
    print(string.format("[FrogFlagReader] Found class: %s\n", class:GetFullName()))

    local okConstruct, instance = pcall(function()
        return StaticConstructObject(class, player, 0, 0, 0, nil, false, false, nil)
    end)
    if not okConstruct or not instance or not instance:IsValid() then
        print(string.format("[FrogFlagReader] StaticConstructObject: ok=%s valid=%s\n",
            tostring(okConstruct), tostring(instance and instance:IsValid())))
        return
    end
    print(string.format("[FrogFlagReader] Constructed instance: %s\n", instance:GetFullName()))

    local okInit, initErr = pcall(function() instance:OnInitialize() end)
    print(string.format("[FrogFlagReader] instance:OnInitialize() ok=%s err=%s\n",
        tostring(okInit), tostring(initErr)))

    G_DebugMenuStateInstance = instance
    print("[FrogFlagReader] Stored as G_DebugMenuStateInstance for the fire-cheat keybind.\n")
end

-- Confirmed live: calling OnExecuteFullAmmo right after only
-- OnInitialize() crashed the actual game engine (no Lua error caught --
-- the log just stops after the "Before" ammo read). OnInitialize() is the
-- generic UIcsDebugMenuState base setup; BP_PlayerDebugMenuState_C's own
-- CreateDebugMenu() is presumably what actually wires up whatever
-- reference(s) OnExecuteFullAmmo depends on (child UIcsDebugMenuBool/Enum
-- values, event bindings, etc -- see CreateDebugMenu() in
-- BP_PlayerDebugMenuState.hpp). Kept as its own separate step since it's
-- also a Blueprint-graph call and could crash on its own.
local function TryCreateDebugMenu()
    if not G_DebugMenuStateInstance or not G_DebugMenuStateInstance:IsValid() then
        print("[FrogFlagReader] TryCreateDebugMenu: no constructed instance, run Ctrl+K first\n")
        return
    end
    local okCreate, createErr = pcall(function() G_DebugMenuStateInstance:CreateDebugMenu() end)
    print(string.format("[FrogFlagReader] instance:CreateDebugMenu() ok=%s err=%s\n",
        tostring(okCreate), tostring(createErr)))
end

-- Separate, deliberate third step -- only run this after
-- TryConstructPlayerDebugMenu AND TryCreateDebugMenu have both printed
-- success. OnExecuteFullAmmo is a Blueprint-graph function (has
-- UberGraphFrame), so a real engine crash here (not just a Lua error) is
-- possible if the BP graph dereferences something we still haven't set
-- up -- this is the actual experiment, not a safe probe.
local function TryFullAmmoCheat()
    if not G_DebugMenuStateInstance or not G_DebugMenuStateInstance:IsValid() then
        print("[FrogFlagReader] TryFullAmmoCheat: no constructed instance, run Ctrl+K first\n")
        return
    end

    -- Confirmed live twice: calling OnExecuteFullAmmo(nil, ...) crashes the
    -- engine even after CreateDebugMenu(). Real debug-menu usage always
    -- passes a live UIcsDebugMenuValue widget for this first param, so the
    -- BP graph likely dereferences it with no null-check. Construct a real
    -- (blank) UIcsDebugMenuValue via StaticConstructObject -- same working
    -- primitive from Ctrl+K -- instead of passing nil.
    local okValueClass, valueClass = pcall(function()
        return FindObject("Class", "IcsDebugMenuCallback")
    end)
    if not okValueClass or not valueClass or not valueClass:IsValid() then
        print(string.format("[FrogFlagReader] FindObject(Class, IcsDebugMenuCallback): ok=%s valid=%s\n",
            tostring(okValueClass), tostring(valueClass and valueClass:IsValid())))
        return
    end

    local okDummy, dummyValue = pcall(function()
        return StaticConstructObject(valueClass, G_DebugMenuStateInstance, 0, 0, 0, nil, false, false, nil)
    end)
    if not okDummy or not dummyValue or not dummyValue:IsValid() then
        print(string.format("[FrogFlagReader] StaticConstructObject(IcsDebugMenuCallback): ok=%s valid=%s\n",
            tostring(okDummy), tostring(dummyValue and dummyValue:IsValid())))
        return
    end
    print(string.format("[FrogFlagReader] Constructed dummy value: %s\n", dummyValue:GetFullName()))

    local weapon = nil
    pcall(function()
        local player = UEHelpers.GetPlayer()
        local equip = player.m_equipController
        weapon = equip:GetCurrentWeapon()
    end)
    local okBefore, before = pcall(function() return weapon:GetLoadedAmmoCount() end)
    print(string.format("[FrogFlagReader] Before: GetLoadedAmmoCount ok=%s value=%s\n",
        tostring(okBefore), tostring(before)))

    local okCall, callErr = pcall(function()
        G_DebugMenuStateInstance:OnExecuteFullAmmo(dummyValue, FText(""), true)
    end)
    print(string.format("[FrogFlagReader] OnExecuteFullAmmo ok=%s err=%s\n",
        tostring(okCall), tostring(callErr)))

    local okAfter, after = pcall(function() return weapon:GetLoadedAmmoCount() end)
    print(string.format("[FrogFlagReader] After: GetLoadedAmmoCount ok=%s value=%s\n",
        tostring(okAfter), tostring(after)))
end

-- Manual triggers:
--   Ctrl+Num9: read known counters
--   Ctrl+Num8: dump every function/property on the subsystem's full class hierarchy
--   Ctrl+Num7: milestone 3 write test v1 (GakoSetCollected on a live duck -- one-shot, kept for reference)
--   Ctrl+Num6: milestone 3 write test v2 (Gako_Life decrement/restore -- repeatable)
--   Ctrl+Num2: milestone 5 probe -- dump any live KerotanComponent instances + their properties
--   Ctrl+Num1: milestone 5 probe -- dump the real parameter list of the Kerotan status functions
RegisterKeyBind(Key.NUM_NINE, {ModifierKey.CONTROL}, ReadKerotanStatus)
RegisterKeyBind(Key.NUM_EIGHT, {ModifierKey.CONTROL}, DumpKerotanSubsystemMembers)
RegisterKeyBind(Key.NUM_SEVEN, {ModifierKey.CONTROL}, TestGakoWrite)
RegisterKeyBind(Key.NUM_SIX, {ModifierKey.CONTROL}, TestGakoLifeWrite)
RegisterKeyBind(Key.NUM_TWO, {ModifierKey.CONTROL}, DumpKerotanComponents)
RegisterKeyBind(Key.NUM_ONE, {ModifierKey.CONTROL}, DumpKerotanFunctionParams)
RegisterKeyBind(Key.NUM_ZERO, {ModifierKey.CONTROL}, DumpKerotanActors)
RegisterKeyBind(Key.P, {ModifierKey.CONTROL}, DumpPlayerAmmoProperties)
RegisterKeyBind(Key.O, {ModifierKey.CONTROL}, DumpPlayerSubControllers)
RegisterKeyBind(Key.I, {ModifierKey.CONTROL}, DumpWeaponStockedAmmoMap)
RegisterKeyBind(Key.L, {ModifierKey.CONTROL}, ProbeDebugMenuState)
RegisterKeyBind(Key.K, {ModifierKey.CONTROL}, TryConstructPlayerDebugMenu)
RegisterKeyBind(Key.N, {ModifierKey.CONTROL}, TryCreateDebugMenu)
RegisterKeyBind(Key.M, {ModifierKey.CONTROL}, TryFullAmmoCheat)
RegisterKeyBind(Key.U, {ModifierKey.CONTROL}, TryEquipControllerAmmoWrite)
RegisterKeyBind(Key.Y, {ModifierKey.CONTROL}, ReadEquipControllerAmmo)
-- The default Keybinds mod's Ctrl+Num6 -> DumpUSMAP never actually fires:
-- this mod loads first and already claims Ctrl+Num6 for TestGakoLifeWrite,
-- so IsKeyBindRegistered() makes the default wrapper skip it. Call the
-- global DumpUSMAP() directly on its own free key instead, for FModel
-- setup (writes a .usmap next to UE4SS.log).
RegisterKeyBind(Key.T, {ModifierKey.CONTROL}, function()
    local ok, err = pcall(DumpUSMAP)
    print(string.format("[FrogFlagReader] DumpUSMAP() ok=%s err=%s\n", tostring(ok), tostring(err)))
end)

-- Real camo/facepaint state lives on the native UUE4PairingCamouflageManager
-- subsystem (found via CXXHeaderDump's MGS3.hpp), not the raw memory
-- pointer-chain we tried first (that byte didn't match what was actually
-- rendered -- see the conversation this session). Read-only: safe getter
-- calls plus a direct struct-property read, no writes yet.
local function ProbeCamouflageManager()
    local Manager = FindFirstOf("UE4PairingCamouflageManager")
    if not Manager or not Manager:IsValid() then
        print("[FrogFlagReader] ProbeCamouflageManager: no live UE4PairingCamouflageManager found\n")
        return
    end

    local okCloth, cloth = pcall(function() return Manager:GetMgsCloth() end)
    local okFace, face = pcall(function() return Manager:GetMgsFacepaint() end)
    local okNaked, isNaked = pcall(function() return Manager:IsNakedTypeUniform() end)
    print(string.format(
        "[FrogFlagReader] GetMgsCloth ok=%s val=%s | GetMgsFacepaint ok=%s val=%s | IsNakedTypeUniform ok=%s val=%s\n",
        tostring(okCloth), tostring(cloth), tostring(okFace), tostring(face), tostring(okNaked), tostring(isNaked)
    ))

    local okInfo, info = pcall(function() return Manager.CurrentInfo end)
    if okInfo and info then
        local okCamouf, camouf = pcall(function() return info.Camouf end)
        local okFacepaint, facepaint = pcall(function() return info.facepaint end)
        print(string.format(
            "[FrogFlagReader] CurrentInfo.Camouf ok=%s val=%s | CurrentInfo.facepaint ok=%s val=%s\n",
            tostring(okCamouf), tostring(camouf), tostring(okFacepaint), tostring(facepaint)
        ))
    else
        print("[FrogFlagReader] Failed to read CurrentInfo struct\n")
    end
end

RegisterKeyBind(Key.G, {ModifierKey.CONTROL}, ProbeCamouflageManager)

-- UpdateCamouflageByNoPairing is a native (non-Blueprint) function on
-- UUE4PairingCamouflageManager -- much lower crash risk than the debug
-- menu's Blueprint UberGraph functions that crashed the game earlier this
-- session. EFacePaintType/ECamouflageType values come straight from
-- MGS3_enums.hpp: GM_FACEPAINT_NONE=0, GM_CAMOUF_NAKED=11.
local function TrySetNakedNoFacepaint()
    local Manager = FindFirstOf("UE4PairingCamouflageManager")
    if not Manager or not Manager:IsValid() then
        print("[FrogFlagReader] TrySetNakedNoFacepaint: no live UE4PairingCamouflageManager found\n")
        return
    end

    local okBefore, infoBefore = pcall(function() return Manager.CurrentInfo end)
    if okBefore and infoBefore then
        print(string.format(
            "[FrogFlagReader] BEFORE Camouf=%s facepaint=%s\n",
            tostring(infoBefore.Camouf), tostring(infoBefore.facepaint)
        ))
    end

    local okCall, err = pcall(function()
        Manager:UpdateCamouflageByNoPairing(0, 11) -- GM_FACEPAINT_NONE, GM_CAMOUF_NAKED
    end)
    print(string.format("[FrogFlagReader] UpdateCamouflageByNoPairing ok=%s err=%s\n", tostring(okCall), tostring(err)))

    local okAfter, infoAfter = pcall(function() return Manager.CurrentInfo end)
    if okAfter and infoAfter then
        print(string.format(
            "[FrogFlagReader] AFTER Camouf=%s facepaint=%s\n",
            tostring(infoAfter.Camouf), tostring(infoAfter.facepaint)
        ))
    end
end

RegisterKeyBind(Key.H, {ModifierKey.CONTROL}, TrySetNakedNoFacepaint)

-- Also try automatically a few seconds after the mod loads, in case the
-- game is already in a gameplay session. TestGakoWrite is NOT auto-run --
-- it has a real, permanent side effect on the save, so it only runs on the
-- explicit Ctrl+Num7 keybind.
ExecuteWithDelay(5000, ReadKerotanStatus)
ExecuteWithDelay(5500, DumpKerotanSubsystemMembers)
