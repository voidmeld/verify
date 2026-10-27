--!strict
local attachments = require "./capture-attachments"
return [====[
local Http = game:GetService("HttpService")
local function vector(value) return {value.X, value.Y, value.Z} end
local function frame(value) return {value:GetComponents()} end
local function map(value)
 if value.SourceType == Enum.ContentSourceType.None then return "" end
 assert(value.SourceType == Enum.ContentSourceType.Uri, "content map has no durable URI")
 return value.Uri
end
local function snapshot(root)
 local objects = {root}
 local function visit(parent) for _, child in parent:GetChildren() do table.insert(objects, child); visit(child) end end
 visit(root)
 local indices = {}
 for index, object in objects do indices[object] = index end
 local rows = {}
 for index, object in objects do
  local row = {name=object.Name, className=object.ClassName, parent=indices[object.Parent]}
  if object:IsA("Model") then local box, size = object:GetBoundingBox(); row.pivot=frame(object:GetPivot()); row.box=frame(box); row.size=vector(size); row.primaryPart=indices[object.PrimaryPart] end
  if object:IsA("BasePart") then row.cframe=frame(object.CFrame); row.pivotOffset=frame(object.PivotOffset); row.size=vector(object.Size); row.canCollide=object.CanCollide; row.canQuery=object.CanQuery; row.material=object.Material.Name; row.materialVariant=object.MaterialVariant end
  if object:IsA("MeshPart") then row.meshId=object.MeshId; row.textureId=object.TextureID; row.meshSize=vector(object.MeshSize); row.collisionFidelity=object.CollisionFidelity.Name end
  if object:IsA("SurfaceAppearance") then row.colorMap=map(object.ColorMapContent); row.normalMap=map(object.NormalMapContent); row.metalnessMap=map(object.MetalnessMapContent); row.roughnessMap=map(object.RoughnessMapContent); row.alphaMode=object.AlphaMode.Name end
  if object:IsA("SpecialMesh") then row.meshId=object.MeshId; row.textureId=object.TextureId; row.scale=vector(object.Scale); row.offset=vector(object.Offset) end
  if object:IsA("Attachment") then row.cframe=frame(object.CFrame) end
  if object:IsA("Bone") then row.transform=frame(object.Transform) end
  if object:IsA("Motor6D") then row.c0=frame(object.C0); row.c1=frame(object.C1); row.transform=frame(object.Transform); row.part0=indices[object.Part0]; row.part1=indices[object.Part1] end
  if object:IsA("AnimationConstraint") then row.attachment0=indices[object.Attachment0]; row.attachment1=indices[object.Attachment1]; row.transform=frame(object.Transform) end
   if object:IsA("KeyframeSequence") then row.loop=object.Loop; row.priority=object.Priority.Name end
   if object:IsA("Keyframe") then row.time=object.Time end
   if object:IsA("Pose") then row.cframe={object.CFrame:GetComponents()}; row.weight=object.Weight; row.easingStyle=object.EasingStyle.Name; row.easingDirection=object.EasingDirection.Name end

  rows[index]=row
 end
 return rows
end
local root = game.ReplicatedStorage.NativeContent
]====] .. attachments .. [====[
local Core, Roblox = require(root.src.core), require(root.src.roblox)
local harness = Core.createHarness {now = os.clock}
harness:case("native content facts", function(check)
 local captured = captureAttachments(check)
 local output = {schemaVersion=1, engineVersion=version(), placeId=game.PlaceId, placeVersion=game.PlaceVersion, gameId=game.GameId, rows={}}
 for _, request in requests do
  local loaded
  local ok, facts = pcall(function()
   if request.kind == "model" then
    loaded = game:GetService("InsertService"):LoadAssetVersion(request.version)
   elseif request.kind == "mesh" then
    loaded = game:GetService("AssetService"):CreateMeshPartAsync(Content.fromUri("rbxassetid://" .. request.id), {CollisionFidelity=Enum.CollisionFidelity.Box})
   else
    loaded = game:GetService("KeyframeSequenceProvider"):GetKeyframeSequenceAsync("rbxassetid://" .. request.id)
   end
   loaded.Parent = nil
   return snapshot(loaded)
  end)
  if loaded then loaded:Destroy() end
  table.insert(output.rows, {request=request, ok=ok, facts=if ok then facts else nil, refusal=if not ok then tostring(facts) else nil})
  task.wait()
 end
 require(root.src.roblox["content-facts"]).validate(output)
 local encoded = Http:JSONEncode(output)
 captured.attach("facts.json", "application/json", encoded)
 captured.finish()
 check:expect(#output.rows):toBe(#requests)
end)
return Http:JSONEncode(Roblox.reportChannel.envelope(runId, harness:run {executor="native-content-capture", environment={engineVersion=version()}, attachments=Parts.limits}))
]====]
