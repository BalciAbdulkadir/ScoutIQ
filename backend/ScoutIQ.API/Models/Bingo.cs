using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace ScoutIQ.API.Models
{
    // Oyuncunun kazandığı bir başlık (015_onem_verileri.sql). Bingo'nun başarı kategorileri için okunur.
    [Table("oyuncu_basarilari")]
    public class OyuncuBasarisi : BaseModel
    {
        [Column("oyuncu_id")]
        public string OyuncuId { get; set; } = string.Empty;

        [Column("baslik")]
        public string Baslik { get; set; } = string.Empty;
    }

    // Bingo destesindeki bir oyuncunun uyduğu kutular (020_bingo.sql). Uygulamaya kapalıdır:
    // hamleler bingo_hamle fonksiyonunda bu tabloya göre kontrol edilir.
    [Table("bingo_eslesmeleri")]
    public class BingoEslesmesi : BaseModel
    {
        [Column("oyun_id")]
        public string OyunId { get; set; } = string.Empty;

        // Destedeki sıra, 1'den başlar
        [Column("sira")]
        public int Sira { get; set; }

        // Oyuncunun uyduğu kutular (0-15)
        [Column("hucreler")]
        public int[] Hucreler { get; set; } = System.Array.Empty<int>();
    }
}
