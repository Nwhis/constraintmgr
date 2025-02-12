CMgr.WritableValues = {
    Ang = "a", angularlimit = "f", addlength = "f",
    Bone1 = "i", Bone2 = "i", Bone4 = "i",
    LPos1 = "v", LPos2 = "v", LPos4 = "v",
    WPos2 = "v", WPos3 = "v",
    amplitude = "f", period = "f",
    bwd_bind = "i", fwd_bind = "i",
    numpadkey_bwd = "i", numpadkey_fwd = "i",
    bwd_speed = "f", fwd_speed = "f", speed = "f",
    color = "c", material = "s",
    constant = "f", damping = "f", rdamping = "f",
    direction = "i",
    forcelimit = "f", torquelimit = "f",
    forcescale = "f", forcetime = "f",
    fixed = "y", friction = "f", torque = "f",
    length = "f", Length1 = "f", Length2 = "f",
    LocalAxis = "v",
    nocollide = "y",
    onlyrotation = "y",
    rigid = "b",
    stretchonly = "y", starton = "b", is_on = "b",
    width = "f",
    xfric = "f", xmax = "f", xmin = "f",
    yfric = "f", ymax = "f", ymin = "f",
    zfric = "f", zmax = "f", zmin = "f",
    toggle = "b",
    key = "i"
}
CMgr.ReadOnlyValues = {
    Constraint = "s", _curlength = "f",
    Ent1 = "e", Ent2 = "e", Ent4 = "e",
    Type = "s", pl = "e",
    MyCrtl = "e"
}
CMgr.ValidValues = table.Merge(CMgr.WritableValues,CMgr.ReadOnlyValues)

CMgr.WriteVector3 = function(vec)
    net.WriteFloat(vec[1]) net.WriteFloat(vec[2]) net.WriteFloat(vec[3])
end
CMgr.WriteColor3 = function(tbl)
    tbl = {tbl.r,tbl.g,tbl.b}
    for _,v in ipairs(tbl) do net.WriteUInt(math.Clamp(v,0,255),8) end
end
CMgr.ReadVector3 = function() return Vector(net.ReadFloat(),net.ReadFloat(),net.ReadFloat()) end
CMgr.ReadColor3 = function() return Color(net.ReadUInt(8),net.ReadUInt(8),net.ReadUInt(8),255) end
CMgr.GetType = function(var) return IsColor(var) and "Color" or type(var) end
CMgr.TextToTable = function(tbl,tbl_ref) -- turn a table of text into a table of data, using a reference table
    local out = {}
    for k,v in pairs(tbl) do
        local t_ref = CMgr.GetType(tbl_ref[k])
        local try = true
        if v == "" and t_ref ~= "string" then continue end -- totally blank input (that's not supposed to be), just skip it
        if type(v) ~= "string" and type(v) == t_ref then try = false end -- this isn't even a string somehow, yay
        if try and t_ref == "boolean" and tostring(tobool(v)) == v then v = tobool(v) try = false end -- definitely a bool
        if try and string.find("Angle Color Vector",t_ref) then -- something with 3 numbers
            v = string.Split(v," ")
            if t_ref == "Color" then
                local c = {}
                for i = 1, 3 do
                    c[i] = v[i] and (tonumber(v[i]) or 0) or 0
                end
                c[4] = 255
                v = Color(unpack(c))
            elseif t_ref == "Vector" then v = Vector(v)
            else v = Angle(v) end
            try = false
        end
        if try and tonumber(v) then v = tonumber(v) try = false end -- try to convert to a basic number
        if try and t_ref ~= "string" then continue end -- whatever this is, we don't want it
        out[k] = v
    end
    return out
end
CMgr.FilterDuplicates = function(tbl,tbl_ref) -- removes any data that's not different from the reference table
    local out = {}
    for k,v in pairs(tbl) do
        if tbl_ref[k] == v then continue end
        out[k] = v
    end
    return out
end
CMgr.FilterTableType = function(tbl,filter) -- removes anything with a type matching the filter
    local out = {}
    for k,v in pairs(tbl) do
        local t = CMgr.GetType(v)
        if string.find(filter,t) then continue end
        out[k] = v
    end
    return out
end
CMgr.FilterTableKey = function(tbl,filter) -- removes anything missing the required key
    local out = {}
    for k,v in pairs(tbl) do
        if not v[filter] then continue end
        out[k] = v
    end
    return out
end
CMgr.FilterValid = function(tbl,strict) -- removes anything not allowed to be networked
    local out = {}
    local filter = strict and CMgr.WritableValues or CMgr.ValidValues
    for k,v in pairs(tbl) do
        if not filter[k] then continue end
        out[k] = v
    end
    return out
end
local read_funcs = {
    a = net.ReadAngle,
    b = net.ReadBool,
    c = CMgr.ReadColor3,
    e = net.ReadEntity,
    f = net.ReadFloat,
    i = function() return net.ReadInt(24) end,
    s = net.ReadString,
    t = CMgr.ReadTable,
    v = CMgr.ReadVector3,
    y = net.ReadBit
}
local write_funcs = {
    a = net.WriteAngle,
    b = net.WriteBool,
    c = CMgr.WriteColor3,
    e = function(i) i = type(i) == "number" and Entity(i) or i net.WriteEntity(i) end,
    f = net.WriteFloat,
    i = function(i) net.WriteInt(i,24) end,
    s = function(i) net.WriteString(tostring(i)) end,
    t = CMgr.WriteTable,
    v = CMgr.WriteVector3,
    y = net.WriteBit
}
CMgr.WriteTable = function(tbl)
    net.WriteUInt(table.Count(tbl),10)
    for k,v in pairs(tbl) do
        net.WriteString(k)
        write_funcs[CMgr.ValidValues[k]](v)
    end
end
CMgr.ReadTable = function()
    local count = net.ReadUInt(10)
    local tbl = {}
    for i = 1, count do
        local k = net.ReadString()
        local v = read_funcs[CMgr.ValidValues[k]]()
        tbl[k] = v
    end
    return tbl
end
CMgr.GetPlayerBool = function(ply,property)
    if not property then property = ply ply = LocalPlayer() end
    return tobool(ply:GetInfoNum("constraintmgr_" .. property,0))
end