-- Sunucu tarafı giriş noktası.
-- Studio'da ServerScriptService > Server (Script) olarak görünür.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Selam = require(ReplicatedStorage.Shared.Selam)

print(Selam.mesaj("sunucu"))
