# SQL dosyaları artık repoda tutulmuyor

Supabase'e çalıştırdığımız `supabase/migrations/*.sql` dosyaları (001–031) repodan çıkarıldı. Bundan sonra yazılacak SQL dosyaları da repoya girmeyecek. Dosyalar silinmedi: herkesin bilgisayarında `supabase/migrations/` içinde durmaya devam edecek, sadece git takip etmeyecek.

Eski commit'lerin geçmişinde dosyalar duruyor; geçmiş yeniden yazılmadı, force push yok. Supabase'deki veritabanı da etkilenmez.

## Neden senin de bir şey yapman gerekiyor

Dosyaları repodan çıkaran değişiklik `main`'e girdikten sonra `git pull` yaptığında git bu 31 dosyayı **senin bilgisayarından siler**. Aşağıdaki adımlar dosyaları yerinde tutmak ve yeni SQL'lerin yanlışlıkla repoya girmesini önlemek için.

## Yapılacaklar

### 1. Pull'dan önce SQL dosyalarını yedekle

Proje kök klasöründe (PowerShell):

```powershell
Copy-Item -Recurse supabase\migrations $env:TEMP\scoutiq_sql_yedek
```

Pull'dan önce yedeklemeyi unuttuysan sorun değil, 3. adımdaki "B yolu" dosyaları geri getirir.

### 2. Değişikliği çek

```powershell
git checkout main
git pull
```

Bu noktada `supabase/migrations/` içindeki .sql dosyaları silinmiş olur.

### 3. Dosyaları geri koy

**A yolu: yedek aldıysan**

```powershell
Copy-Item $env:TEMP\scoutiq_sql_yedek\*.sql supabase\migrations\
```

**B yolu: yedek almadıysan**

Dosyaları, hepsinin repoda olduğu son commit'ten (`e7c108d`) geri getir:

```powershell
git restore --source=e7c108d --worktree -- supabase/migrations
```

`--worktree` dosyaları sadece diske yazar, git'e tekrar eklemez.

### 4. SQL dosyalarını git'ten gizle

`.git/info/exclude` dosyasının sonuna şu satırı ekle:

```
/supabase/migrations/*.sql
```

PowerShell ile:

```powershell
Add-Content -Path .git\info\exclude -Value "/supabase/migrations/*.sql" -Encoding ascii
```

`.git/info/exclude`, `.gitignore` gibi çalışır ama sadece senin bilgisayarında geçerlidir, repoya gitmez. `kurallar/` klasörünü de aynı yöntemle gizliyoruz. `.gitignore`'a dokunmuyoruz.

### 5. Kontrol et

```powershell
git status
git check-ignore -v supabase/migrations/001_temel_veri_duzeltmeleri.sql
```

- `git status` .sql dosyalarını ne "silindi" ne de "untracked" olarak göstermemeli.
- `git check-ignore` şu satıra benzer bir çıktı vermeli: `.git/info/exclude:...:/supabase/migrations/*.sql`

`supabase/migrations/` içinde 001'den 031'e kadar dosyaların durduğunu da kontrol et.

## Bundan sonra

- Yeni bir SQL dosyası yazınca yine `supabase/migrations/` içine koy. Git onu görmez, commit'e girmez.
- `git add -f` ile SQL dosyası ekleme.
- PR açıklamasında hangi SQL dosyasının hangi sırayla çalıştırılacağını dosya adıyla yaz. Dosyayı da diğer kişiye repo dışından (mesajla) gönder.
- Numaralar çakışmasın diye yeni dosyaya numara vermeden önce birbirimize son numarayı soralım. Şu an son numara 031.
