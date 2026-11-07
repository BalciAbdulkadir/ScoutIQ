using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace ScoutIQ.API.Models
{
    [Table("kariyer_gecmisi")]
    public class KariyerGecmisi : BaseModel
    {
        [Column("id")]
        public string Id { get; set; } = string.Empty;

        [Column("oyuncu_id")]
        public string OyuncuId { get; set; } = string.Empty;

        [Column("kulup_id")]
        public string KulupId { get; set; } = string.Empty;

        // Oyuncunun bu kulüpte oynadığı son sezon (2026 = 2026/27)
        [Column("bitis_yili")]
        public int? BitisYili { get; set; }

        // Oyuncunun bu kulüpte çıktığı resmi maç sayısı. 0: kadroda olup hiç oynamamış, null: istatistiği çekilmemiş
        [Column("mac_sayisi")]
        public int? MacSayisi { get; set; }

        // Soru kademesi hesaplanırken sadece kulüpte gerçekten oynamış oyuncular sayılır.
        // Maç sayısı bilinmiyorsa oynamış kabul edilir. Cevap kontrolü ise bütün kariyer kayıtlarına bakar.
        public bool Oynadi => MacSayisi is null or > 0;
    }
}
