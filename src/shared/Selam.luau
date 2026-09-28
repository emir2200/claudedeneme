-- Sunucu ve istemcinin ikisinin de kullanabildiği ortak modül.
-- Studio'da ReplicatedStorage > Shared > Selam olarak görünür.

local Selam = {}

function Selam.mesaj(kimden: string): string
	return `Selam, {kimden} tarafından! Rojo bağlantısı çalışıyor.`
end

return Selam
