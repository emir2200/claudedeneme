# claudedeneme

Roblox oyun kodları için bir [Rojo](https://rojo.space) projesi. Luau script'leri bu depoda
yazılır, Rojo ile Roblox Studio'ya canlı olarak senkronlanır.

## Klasör yapısı

| Depodaki yol                 | Studio'daki yeri                                   | Türü        |
| ---------------------------- | -------------------------------------------------- | ----------- |
| `src/server/`                | `ServerScriptService > Server`                     | Script      |
| `src/client/`                | `StarterPlayer > StarterPlayerScripts > Client`    | LocalScript |
| `src/shared/`                | `ReplicatedStorage > Shared`                       | Folder      |

Dosya adları Studio'daki türü belirler:

- `isim.server.luau` → Script (sunucu)
- `isim.client.luau` → LocalScript (istemci)
- `isim.luau` → ModuleScript
- Bir klasördeki `init.server.luau` / `init.client.luau` / `init.luau`, klasörün kendisini o script'e dönüştürür.

## Kurulum (bir kez)

1. **Rokit'i kurun** (Rojo gibi araçları yöneten küçük bir program).
   Windows'ta PowerShell'i açıp şunu çalıştırın:

   ```powershell
   Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
   ```

   macOS / Linux:

   ```sh
   curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
   ```

   Kurulumdan sonra terminali kapatıp yeniden açın.

2. **Depoyu indirin ve araçları kurun:**

   ```sh
   git clone https://github.com/emir2200/claudedeneme.git
   cd claudedeneme
   rokit install
   ```

3. **Rojo eklentisini Studio'ya kurun:**

   ```sh
   rojo plugin install
   ```

   Studio açıksa kapatıp yeniden açın. Üstteki **Plugins** sekmesinde Rojo düğmesi görünmelidir.

## Günlük kullanım

1. Proje klasöründe Rojo sunucusunu başlatın:

   ```sh
   rojo serve
   ```

2. Studio'da bir place açın (boş bir Baseplate yeterli), **Plugins > Rojo > Connect**'e tıklayın.
3. **Play**'e basın. Output penceresinde şunları görmelisiniz:

   ```
   Selam, sunucu tarafından! Rojo bağlantısı çalışıyor.
   Selam, istemci tarafından! Rojo bağlantısı çalışıyor.
   ```

`rojo serve` açık kaldığı sürece `src/` altındaki her değişiklik Studio'ya anında yansır.
Depoya yeni kod geldiğinde `git pull` yapmanız yeterli.

## Place dosyası üretmek (isteğe bağlı)

Studio'da açılabilen bir `.rbxl` dosyası oluşturmak için:

```sh
rojo build -o oyun.rbxl
```
