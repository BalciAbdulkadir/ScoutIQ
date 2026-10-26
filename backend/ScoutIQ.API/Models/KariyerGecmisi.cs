using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace ScoutIQ.API.Models
{
    [Table("kariyer_gecmisi")]
    public class KariyerGecmisi : BaseModel
    {
        [Column("oyuncu_id")]
        public string OyuncuId { get; set; } = string.Empty;

        [Column("kulup_id")]
        public string KulupId { get; set; } = string.Empty;

        // Oyuncunun bu kulüpte oynadığı son sezon (2026 = 2026/27)
        [Column("bitis_yili")]
        public int? BitisYili { get; set; }
    }
}
