--!strict

local Datatypes = require "./datatypes"
local Types = require "./environment-types"

return table.freeze(({
	Object = { creatable = false },
	Instance = { super = "Object", creatable = false },
	Folder = { super = "Instance" },
	BindableFunction = { super = "Instance", access = { OnInvoke = "callback" }, methods = { Invoke = true } },
	RemoteFunction = {
		super = "Instance",
		access = { OnServerInvoke = "callback", OnClientInvoke = "callback" },
		methods = { InvokeServer = true, InvokeClient = true },
	},
	Model = { super = "Instance", properties = { PrimaryPart = false } },
	Configuration = { super = "Instance" },
	BasePart = {
		super = "Instance",
		creatable = false,
		properties = { Transparency = 0, Anchored = false, CanCollide = true },
		events = { "Touched", "TouchEnded" },
	},
	Part = { super = "BasePart" },
	MeshPart = { super = "BasePart" },
	GuiObject = {
		super = "Instance",
		creatable = false,
		properties = {
			Visible = true,
			BackgroundTransparency = 0,
			BackgroundColor3 = Datatypes.Color3.new(1, 1, 1),
			LayoutOrder = 0,
			ZIndex = 1,
			Size = Datatypes.UDim2.new(0, 0, 0, 0),
			Position = Datatypes.UDim2.new(0, 0, 0, 0),
			AnchorPoint = Datatypes.Vector2.new(0, 0),
			Active = false,
			ClipsDescendants = false,
		},
		events = { "InputBegan", "InputEnded", "MouseEnter", "MouseLeave" },
	},
	Frame = { super = "GuiObject" },
	CanvasGroup = { super = "GuiObject", properties = { GroupTransparency = 0 } },
	ScrollingFrame = {
		super = "GuiObject",
		properties = {
			CanvasSize = Datatypes.UDim2.new(0, 0, 0, 0),
			CanvasPosition = Datatypes.Vector2.new(0, 0),
			ScrollingEnabled = true,
			ScrollBarThickness = 12,
		},
	},
	TextBox = {
		super = "GuiObject",
		properties = { Text = "", PlaceholderText = "", ClearTextOnFocus = true },
		events = { "Focused", "FocusLost" },
	},
	UIListLayout = {
		super = "Instance",
		properties = { Padding = Datatypes.UDim.new(0, 0), SortOrder = false, FillDirection = false },
	},
	UIPadding = {
		super = "Instance",
		properties = {
			PaddingLeft = Datatypes.UDim.new(0, 0),
			PaddingRight = Datatypes.UDim.new(0, 0),
			PaddingTop = Datatypes.UDim.new(0, 0),
			PaddingBottom = Datatypes.UDim.new(0, 0),
		},
	},
	TextLabel = { super = "GuiObject", properties = { Text = "" } },
	TextButton = {
		super = "GuiObject",
		properties = { Text = "" },
		events = { "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up" },
	},
	ImageLabel = { super = "GuiObject", properties = { Image = "" } },
	ImageButton = {
		super = "GuiObject",
		properties = { Image = "" },
		events = { "Activated", "MouseButton1Click" },
	},
	ScreenGui = { super = "Instance", properties = { Enabled = true } },
	Humanoid = { super = "Instance", properties = { Health = 100, MaxHealth = 100 } },
	Animation = { super = "Instance", properties = { AnimationId = "" } },
	AnimationTrack = {
		super = "Instance",
		properties = {
			Animation = false,
			IsPlaying = false,
			Speed = 1,
			Weight = 1,
			TimePosition = 0,
			Looped = false,
		},
		events = { "Stopped", "Ended", "DidLoop", "KeyframeReached" },
	},
} :: unknown) :: { [string]: Types.ClassSpec })
