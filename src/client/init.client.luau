-- İstemci tarafı giriş noktası.
-- Studio'da StarterPlayer > StarterPlayerScripts > Client (LocalScript) olarak görünür.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Selam = require(ReplicatedStorage.Shared.Selam)

print(Selam.mesaj("istemci"))
