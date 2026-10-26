--!strict

local Datatypes = require "./datatypes"
local Types = require "./environment-types"

local textChannelAccess: { [string]: "read" | "write" | "none" | "callback" } = { ShouldDeliverCallback = "callback" }
local textChatServiceAccess: { [string]: "read" | "write" | "none" | "callback" } = { OnIncomingMessage = "callback" }
local bindableFunctionAccess: { [string]: "read" | "write" | "none" | "callback" } = { OnInvoke = "callback" }
local bindableFunctionMethods: { [string]: unknown } = { Invoke = true }
local remoteFunctionAccess: { [string]: "read" | "write" | "none" | "callback" } =
	{ OnServerInvoke = "callback", OnClientInvoke = "callback" }
local remoteFunctionMethods: { [string]: unknown } = { InvokeServer = true, InvokeClient = true }
local modelProperties: { [string]: unknown } = { PrimaryPart = false }
local basePartProperties: { [string]: unknown } = { Transparency = 0, Anchored = false, CanCollide = true }
local guiObjectProperties: { [string]: unknown } = {
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
}
local canvasGroupProperties: { [string]: unknown } = { GroupTransparency = 0 }
local scrollingFrameProperties: { [string]: unknown } = {
	CanvasSize = Datatypes.UDim2.new(0, 0, 0, 0),
	CanvasPosition = Datatypes.Vector2.new(0, 0),
	ScrollingEnabled = true,
	ScrollBarThickness = 12,
}
local scrollingFrameMethods: { [string]: unknown } = { GetScrollVelocity = true, ResetScrollVelocity = true }
local textBoxProperties: { [string]: unknown } = { Text = "", PlaceholderText = "", ClearTextOnFocus = true }
local uiListLayoutProperties: { [string]: unknown } =
	{ Padding = Datatypes.UDim.new(0, 0), SortOrder = false, FillDirection = false }
local uiPaddingProperties: { [string]: unknown } = {
	PaddingLeft = Datatypes.UDim.new(0, 0),
	PaddingRight = Datatypes.UDim.new(0, 0),
	PaddingTop = Datatypes.UDim.new(0, 0),
	PaddingBottom = Datatypes.UDim.new(0, 0),
}
local textLabelProperties: { [string]: unknown } = { Text = "" }
local textButtonProperties: { [string]: unknown } = { Text = "" }
local imageLabelProperties: { [string]: unknown } = { Image = "" }
local imageButtonProperties: { [string]: unknown } = { Image = "" }
local screenGuiProperties: { [string]: unknown } = { Enabled = true }
local humanoidProperties: { [string]: unknown } = { Health = 100, MaxHealth = 100 }
local animationProperties: { [string]: unknown } = { AnimationId = "" }
local animationTrackProperties: { [string]: unknown } = {
	Animation = false,
	IsPlaying = false,
	Speed = 1,
	Weight = 1,
	TimePosition = 0,
	Looped = false,
}

local classes: { [string]: Types.ClassSpec } = {
	Object = { creatable = false },
	Instance = { super = "Object", creatable = false },
	Folder = { super = "Instance" },
	TextChannel = { super = "Instance", access = textChannelAccess },
	TextChatService = { super = "Instance", creatable = false, access = textChatServiceAccess },
	BindableFunction = { super = "Instance", access = bindableFunctionAccess, methods = bindableFunctionMethods },
	RemoteFunction = {
		super = "Instance",
		access = remoteFunctionAccess,
		methods = remoteFunctionMethods,
	},
	Model = { super = "Instance", properties = modelProperties },
	Configuration = { super = "Instance" },
	BasePart = {
		super = "Instance",
		creatable = false,
		properties = basePartProperties,
		events = { "Touched", "TouchEnded" },
	},
	Part = { super = "BasePart" },
	MeshPart = { super = "BasePart" },
	GuiObject = {
		super = "Instance",
		creatable = false,
		properties = guiObjectProperties,
		events = { "InputBegan", "InputEnded", "MouseEnter", "MouseLeave" },
	},
	Frame = { super = "GuiObject" },
	CanvasGroup = { super = "GuiObject", properties = canvasGroupProperties },
	ScrollingFrame = {
		super = "GuiObject",
		properties = scrollingFrameProperties,
		methods = scrollingFrameMethods,
	},
	TextBox = {
		super = "GuiObject",
		properties = textBoxProperties,
		events = { "Focused", "FocusLost" },
	},
	UIListLayout = {
		super = "Instance",
		properties = uiListLayoutProperties,
	},
	UIPadding = {
		super = "Instance",
		properties = uiPaddingProperties,
	},
	TextLabel = { super = "GuiObject", properties = textLabelProperties },
	TextButton = {
		super = "GuiObject",
		properties = textButtonProperties,
		events = { "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up" },
	},
	ImageLabel = { super = "GuiObject", properties = imageLabelProperties },
	ImageButton = {
		super = "GuiObject",
		properties = imageButtonProperties,
		events = { "Activated", "MouseButton1Click" },
	},
	ScreenGui = { super = "Instance", properties = screenGuiProperties },
	Humanoid = { super = "Instance", properties = humanoidProperties },
	Animation = { super = "Instance", properties = animationProperties },
	AnimationTrack = {
		super = "Instance",
		properties = animationTrackProperties,
		events = { "Stopped", "Ended", "DidLoop", "KeyframeReached" },
	},
}

return table.freeze(classes)
