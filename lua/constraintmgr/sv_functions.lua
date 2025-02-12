util.AddNetworkString("constraintmgr_notify")
util.AddNetworkString("constraintmgr_tbl")
util.AddNetworkString("constraintmgr_tbl_single")
util.AddNetworkString("constraintmgr_remove")
util.AddNetworkString("constraintmgr_clear")
util.AddNetworkString("constraintmgr_active")
util.AddNetworkString("constraintmgr_replace")
local GetPlayerBool = CMgr.GetPlayerBool
CMgr.Notify = function(ply,str)
    net.Start("constraintmgr_notify")
    net.WriteString(str)
    net.Send(ply)
end
CMgr.SendTable = function(ply,tbl) -- changed selection, send new table of constraints to client
    net.Start("constraintmgr_tbl")
    tbl = CMgr.FilterTableKey(tbl,"Type")
    net.WriteUInt(table.Count(tbl),10)
    for k, v in pairs(tbl) do
        net.WriteUInt(k,10)
        net.WriteString(v.Type)
        local e = {v.Ent1,v.Ent2}
        local p = {v.LPos1,v.LPos2}
        if v.Type == "Ballsocket" then p = {vector_origin,v.LPos} end
        if v.Type == "Pulley" then p = {v.LPos1,v.LPos4} e = {v.Ent1,v.Ent4} end
        for l,b in ipairs(e) do
            net.WriteEntity(b)
            if not p[l] then net.WriteBool(false) continue end
            net.WriteBool(true)
            CMgr.WriteVector3(p[l])
        end
    end
    net.Send(ply)
end
CMgr.SendTableSingle = function(ply,tbl) -- send details of a single constraint
    if not tbl then return end
    if tbl.material and not string.find("Pulley WireHydraulic Slider",tbl.Type) and tbl.LPos1 then
        tbl._curlength = tbl.Ent1:LocalToWorld(tbl.LPos1):Distance(tbl.Ent2:LocalToWorld(tbl.LPos2))
        --[[if not tbl.length and not tbl.Length1 then
            tbl.length = tbl._curlength
        end]]
    end
    if tbl.amplitude then tbl.Length2 = tbl.Length1 + tbl.amplitude end
    if tbl.addlength then tbl.length = tbl.length + tbl.addlength tbl.addlength = nil end
    if not tbl.color and tbl.material then tbl.color = color_white end
    tbl = CMgr.FilterValid(tbl)
    net.Start("constraintmgr_tbl_single")
    CMgr.WriteTable(tbl)
    net.Send(ply)
end
CMgr.CalcConstraints = function(ply,ent) -- Get table of constraints, and include parent/child relations
    if not IsValid(ent) then ply:GetTool("constraintmgr"):Clear() return {},0,0 end
    local tbl = constraint.GetTable(ent)
    tbl = CMgr.FilterTableKey(tbl,"Type") -- ignore pseudo constraints (hydraulic sliders)
    local numconst = table.Count(tbl)
    local numchild = 0
    if GetPlayerBool(ply,"parents") then
        if IsValid(ent:GetParent()) then table.insert(tbl,{Type = "Parent",Ent1 = ent,Ent2 = ent:GetParent()}) end
        local nophys = GetPlayerBool(ply,"parents_nophys")
        for k,v in pairs(ent:GetChildren()) do
            if not IsValid(v) then continue end
            if v:GetParent() ~= ent then continue end
            if not IsValid(v:GetPhysicsObject()) and not nophys then continue end
            numchild = numchild + 1
            table.insert(tbl,{Type = "Child",Ent1 = ent,Ent2 = v})
        end
    end
    ply.constraintmgr_selected = tbl -- Cache the constraints on the player for later (for removing constraints)
    return tbl,numconst,numchild
end