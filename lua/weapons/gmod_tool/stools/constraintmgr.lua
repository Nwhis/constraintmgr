TOOL.Category = "Constraints"
TOOL.Name = "#tool.constraintmgr.name"

TOOL.ClientConVar["persist"] = 0
TOOL.ClientConVar["parents"] = 0
TOOL.ClientConVar["parents_nophys"] = 0
TOOL.ClientConVar["sound"] = 1
TOOL.ClientConVar["cull"] = 1
TOOL.ClientConVar["overlap"] = 0
TOOL.ClientConVar["scale_line"] = 1

local Think

local tool

if CLIENT then
    TOOL.Information = {
        {name = "left_0", stage = 0},
        {name = "left_1", stage = 1},
        {name = "right"},
        {name = "reload", stage = 1},
        {name = "alt",icon = "icon16/control_pause.png"}
    }
    function TOOL.BuildCPanel(panel)
        tool = LocalPlayer():GetTool("constraintmgr")
        local t = "#tool.constraintmgr."
        local c
        panel:CheckBox(t .. "var.persist","constraintmgr_persist").OnChange = function(_,val)
            if not val and not CMgr_Active then
                timer.Create("wait_persist",0.02,1,function()
                    net.Start("constraintmgr_clear")
                    net.SendToServer()
                    if tool then tool:Holster() end
                end)
            end
        end

        local checkno
        c = panel:CheckBox(t .. "var.parents","constraintmgr_parents")
        c.OnChange = function(_,val)
            timer.Create("wait_parent",0.02,1,function()
                checkno:SetEnabled(val)
                net.Start("constraintmgr_tbl")
                net.SendToServer()
            end)
        end
        c:SetTooltip("#tool.constraintmgr.tooltip.fakeconstraint")
        checkno = panel:CheckBox(t .. "var.parents_nophys","constraintmgr_parents_nophys")
        checkno.OnChange = function(_,val)
            timer.Create("wait_parent",0.02,1,function()
                net.Start("constraintmgr_tbl")
                net.SendToServer()
            end)
        end
        checkno:SetTooltip("Holograms, etc.")

        c = vgui.Create("DPanel",panel) c:SetHeight(1) panel:AddItem(c)

        panel:CheckBox(t .. "var.cull","constraintmgr_cull")
        panel:CheckBox(t .. "var.sound","constraintmgr_sound")
        panel:CheckBox(t .. "var.overlap","constraintmgr_overlap"):SetTooltip(t .. "tooltip.overlap")
        panel:NumSlider(t .. "var.scale_line","constraintmgr_scale_line",0,3,1):SetTooltip(t .. "tooltip.scale_line")
    end

    local function CMgrActive(self)
        local a = net.ReadBool()
        if not LocalPlayer() then timer.Simple(5,CMgrActive(self)) return false end
        CMgr_Active = a
        tool = LocalPlayer():GetTool("constraintmgr")
        if not tool then return end
        if a then tool:Deploy() else tool:Holster() end
    end
    net.Receive("constraintmgr_active",CMgrActive)

    function TOOL:SetStage(stage) timer.Create("setstage",0.02,1,function() self._stage = stage end) end
    function TOOL:GetStage() return self._stage or 0 end -- Override clientside Stage functions (they do nothing)

    Think = function()
        if not tool then return end
        if #CMgr_Constraints == 0 then
            if CMgr_LastHover then
                tool:SetStage(0)
                --CMgr_LastHover = nil
            end
            return
        end
        if CMgr_LastHover ~= CMgr_Hovered then
            --CMgr_Selected = 1
            if CMgr_Hovered then tool:SetStage(1) else tool:SetStage(0) end
        end
    end
end

function TOOL:Clear(ply)
    self:ClearObjects()
    if CLIENT then return end
    ply = ply and ply or self:GetOwner()
    ply.constraintmgr_selected = nil
    CMgr.SendTable(ply,{})
    hook.Remove("PreUndo","constraintmgr_undo_" .. ply:UserID())
end
if SERVER then
    net.Receive("constraintmgr_tbl_single",function(_,ply)
        CMgr.SendTableSingle(ply,CMgr.CalcConstraints(ply,ply:GetTool("constraintmgr"):GetEnt(1))[net.ReadUInt(8)])
    end)
    net.Receive("constraintmgr_remove",function(_,ply)
        local c = net.ReadUInt(8)
        c = ply.constraintmgr_selected[c]
        if c then
            if c.Type == "Child" then
                c.Ent2:SetParent()
            elseif c.Type == "Parent" then
                c.Ent1:SetParent()
            else
                SafeRemoveEntity(c.Constraint)
            end
        end
        timer.Create("removed" .. ply:UserID(),0.1,1,function() -- Wait a bit in case it gets spammed
            CMgr.SendTable(ply,CMgr.CalcConstraints(ply,ply:GetTool("constraintmgr"):GetEnt(1)))
        end)
    end)
    net.Receive("constraintmgr_tbl",function(_,ply) -- Requested update from client
        CMgr.SendTable(ply,CMgr.CalcConstraints(ply,ply:GetTool("constraintmgr"):GetEnt(1)))
    end)
    net.Receive("constraintmgr_clear",function(_,ply)
        ply:GetTool("constraintmgr"):Holster()
    end)
    net.Receive("constraintmgr_replace",function(_,ply)
        local oldconst = constraint.GetTable(ply:GetTool("constraintmgr"):GetEnt(1))[net.ReadUInt(8)]
        local modified = CMgr.ReadTable()
        modified = CMgr.FilterValid(modified,true)
        modified = CMgr.FilterDuplicates(modified,oldconst)
        local c
        if table.Count(modified) > 0 then
            local newconst = table.Merge(oldconst,modified)
            c = CMgr.NewConstraint(oldconst.Type,newconst)
            if c then
                c.result = 1
                c:CPPISetOwner(ply)
                undo.ReplaceEntity(oldconst.Constraint,c)
                cleanup.ReplaceEntity(oldconst.Constraint,c)
                SafeRemoveEntity(oldconst.Constraint)
            else
                c = {result = 0}
            end
        else
            c = {result = 2}
        end
        net.Start("constraintmgr_replace") net.WriteUInt(c.result,2) net.Send(ply)
        if c.result ~= 1 then return end
        local waittick = 0
        hook.Add("Tick","cmgr_replaceupdate",function()
            waittick = waittick + 1
            if waittick < 2 then return end
            local t = ply:GetTool("constraintmgr")
            t:LeftClick({Entity = t:GetEnt(1)})
            hook.Remove("Tick","cmgr_replaceupdate")
        end)
    end)
    hook.Add("PlayerDroppedWeapon","constraintmgr_holsterdrop",function(ply,wep)
        if wep:GetClass() == "gmod_tool" then ply:GetTool("constraintmgr"):Holster(true,ply) end
    end)
    hook.Add("PostPlayerDeath","constraintmgr_holsterdeath",function(ply)
        local wep = ply:GetActiveWeapon()
        if wep:GetClass() == "gmod_tool" then ply:GetTool("constraintmgr"):Holster(true,ply) end
    end)
end

function TOOL:LeftClick(trace)
    local ent = trace.Entity
    local ply = self:GetOwner()
    if not IsValid(ent) then
        if ent:IsWorld() then
            self:Clear()
        end
        return ent:IsWorld()
    end
    if ent:IsPlayer() then return false end
    if CLIENT then return true end
    if not IsValid(ent:GetPhysicsObject()) then return false end
    self:SetObject(1,ent,vector_origin,ent:GetPhysicsObject(),0,vector_origin)
    local ctbl,con,chi = CMgr.CalcConstraints(ply,ent)
    CMgr.Notify(ply,tostring(ent) .. " has " .. tostring(con) .. (con == 1 and " constraint" or " constraints") .. (chi > 0 and " and " .. tostring(chi) .. " child" .. (chi == 1 and "" or "ren") or ""))
    if #ctbl == 0 then
        self:Clear()
        return true
    end
    CMgr.SendTable(ply,ctbl)
    hook.Add("PreUndo","constraintmgr_undo_" .. ply:UserID(),function(tbl)
        if not tbl then return end
        if tbl.Owner ~= ply then return end
        local send
        for k,v in ipairs(tbl.Entities) do
            if not IsValid(v) or v:IsConstraint() or v.Type then
                send = true
                break
            end
        end
        if send then
            timer.Create("undo_" .. ply:UserID(),0.1,1,function() CMgr.SendTable(tbl.Owner,CMgr.CalcConstraints(ply,ent)) end)
        end
    end)
    return true
end

function TOOL:RightClick(trace)
    self:Clear()
    return true
end
function TOOL:Deploy()
    if SERVER then -- fix for Deploy not getting called on client when switching tools
        net.Start("constraintmgr_active") net.WriteBool(true) net.Send(self:GetOwner())
        return
    end
    CMgr_Active = true
    tool = self
    CMgr.StartInput()
    CMgr.StartRender()
    hook.Add("Think","constraintmgr_hoverstage",Think)
end
function TOOL:Holster(_,ply)
    if SERVER then -- fix for Holster not getting called on client when switching tools
        net.Start("constraintmgr_active") net.WriteBool(false) net.Send(self:GetOwner())
    end
    if CLIENT then
        CMgr_Active = false
        CMgr.StopInput()
        hook.Remove("Think","constraintmgr_hoverstage")
    end
    if not ply and self:GetClientBool("persist") then return end
    if CLIENT then
        CMgr.StopRender()
    end
    self:Clear(ply)
end
function TOOL:Reload(data)
    if SERVER then return IsValid(self:GetEnt(1)) and true or false end
end