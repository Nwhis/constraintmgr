local GetPlayerBool = CMgr.GetPlayerBool

CMgr_Constraints = {}
CMgr_ConstraintGroups = {}
CMgr_Hovered = nil
CMgr_LastHover = 0
CMgr_Selected = 0

local function GroupConstraints() -- Sort constraints into tables if they share the same entities and positions
    CMgr_Hovered, CMgr_Selected = nil,1
    CMgr_ConstraintGroups = {}
    for k,v in ipairs(CMgr_Constraints) do
        if v.group then continue end
        for l,b in ipairs(CMgr_Constraints) do
            if l == k then continue end
            if not ((v.Ent1 == b.Ent1 and v.Ent2 == b.Ent2) or (v.Ent1 == b.Ent2 and v.Ent2 == b.Ent1)) then continue end
            if not ((v.LPos1 == b.LPos1 and v.LPos2 == b.LPos2) or (v.LPos1 == b.LPos2 and v.LPos2 == b.LPos1)) then continue end
            if b.group then
                table.insert(CMgr_ConstraintGroups[b.group],v)
                v.group = b.group
            else
                v.group = table.insert(CMgr_ConstraintGroups,{v,b})
                b.group = v.group
            end
            break
        end
    end
    local count = 0
    for k,v in ipairs(CMgr_Constraints) do -- Calculate longest name for tooltip rendering
        if v.group then
            local widest = CMgr_ConstraintGroups[v.group][1].widest
            if widest then
                if CMgr_TextWidth[v.Type] > widest then
                    CMgr_ConstraintGroups[v.group][1].widest = CMgr_TextWidth[v.Type]
                end
            else
                CMgr_ConstraintGroups[v.group][1].widest = CMgr_TextWidth[v.Type]
            end
            continue
        end
        v.group = table.insert(CMgr_ConstraintGroups,{v})
        v.widest = CMgr_TextWidth[v.Type]
        count = count + 1
    end
    for k,g in ipairs(CMgr_ConstraintGroups) do
        local v = g[1]
        v.size = {x = 10 + v.widest * 9, y = 8 + #g * 15}
    end
end
net.Receive("constraintmgr_tbl",function() -- List of constraints from server
    local count = net.ReadUInt(10)
    local tbl = {}
    for i = 1, count do
        local id = net.ReadUInt(10)
        tbl[id] = {Index = id}
        tbl[id].Type = net.ReadString()
        CMgr.InitType(tbl[id].Type)
        for j = 1,2 do
            tbl[id]["Ent" .. tostring(j)] = net.ReadEntity()
            if not net.ReadBool() then
                tbl[id].LPos1 = vector_origin
                tbl[id].LPos2 = vector_origin
                continue
            end
            local idx = "LPos" .. tostring(j)
            tbl[id][idx] = CMgr.ReadVector3()
        end
    end
    CMgr_Constraints = tbl
    GroupConstraints()
end)

local PlayerBindPress = function(ply,bind,pressed) -- Detect clicks/scrolls
    if IsFirstTimePredicted() then return end -- Seems to break stuff if you check for (not IsFirstTimePredicted())
    if not pressed then return end
    if not CMgr_Hovered then return end
    if not CMgr_ConstraintGroups then return end
    if bind == "+attack" then
        if #CMgr_ConstraintGroups[CMgr_Hovered] == 1 or CMgr_Selected == 0 then
            CMgr_Selected = 1
        end
        if GetPlayerBool("sound") then
            local ty = CMgr_ConstraintGroups[CMgr_Hovered][CMgr_Selected].Type
            LocalPlayer():EmitSound((ty == "Parent" or ty == "Child") and "buttons/lightswitch2.wav" or "buttons/button9.wav",nil,100,0.5)
        end
        local idx = CMgr_ConstraintGroups[CMgr_Hovered][CMgr_Selected].Index
        CMgr.InspectPopup(idx,CMgr_Constraints[idx])
        return true
    end
    local scroll
    if bind == "invnext" then scroll = 1 elseif bind == "invprev" then scroll = -1 end
    if scroll then
        if GetPlayerBool("sound") then LocalPlayer():EmitSound("weapons/pistol/pistol_empty.wav",nil,120,0.3) end
        CMgr_Selected = CMgr_Selected + scroll
        if CMgr_Selected > #CMgr_ConstraintGroups[CMgr_Hovered] then CMgr_Selected = 1 end
        if CMgr_Selected < 1 then CMgr_Selected = #CMgr_ConstraintGroups[CMgr_Hovered] end
        return true
    end
    if bind == "+reload" then
        net.Start("constraintmgr_remove")
        net.WriteUInt(CMgr_ConstraintGroups[CMgr_Hovered][CMgr_Selected].Index,8)
        net.SendToServer()
        LocalPlayer():EmitSound("buttons/button15.wav",nil,100,0.8)
        if #CMgr_ConstraintGroups[CMgr_Hovered] <= 1 then CMgr_Hovered = nil end
        return false
    end
end
local KeyPress = function(ply,key)
    if key == IN_WALK then CMgr_FreezeRender = true end
end
local KeyRelease = function(ply,key)
    if key == IN_WALK then CMgr_FreezeRender = false end
end
net.Receive("constraintmgr_notify",function()
    chat.AddText(net.ReadString())
end)
CMgr.StartInput = function()
    hook.Add("PlayerBindPress","constraintmgr_bind",PlayerBindPress)
    hook.Add("KeyPress","constraintmgr_keypress",KeyPress)
    hook.Add("KeyRelease","constraintmgr_keyrelease",KeyRelease)
end
CMgr.StopInput = function()
    hook.Remove("PlayerBindPress","constraintmgr_bind")
    hook.Remove("KeyPress","constraintmgr_keypress")
    hook.Remove("KeyRelease","constraintmgr_keyrelease")
end