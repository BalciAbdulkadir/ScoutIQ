using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace ScoutIQ.API.Models
{
    // Bonservis'te tahmin edilen (sağdaki) oyuncunun toplam bonservisi (033_skor_sunucuda.sql).
    // Uygulamaya kapalıdır: cevabı ele vermesin diye soru verisinde yoktur, tahmini sunucudaki fonksiyon kontrol eder.
    [Table("bonservis_cevaplari")]
    public class BonservisCevabi : BaseModel
    {
        [Column("oyun_id")]
        public string OyunId { get; set; } = string.Empty;

        // Sorunun oyundaki sırası, 0'dan başlar (soru verisindeki index)
        [Column("soru_index")]
        public int SoruIndex { get; set; }

        [Column("rakip_bonservis")]
        public long RakipBonservis { get; set; }
    }
}
