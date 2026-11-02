using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace ScoutIQ.API.Models
{
    // Oyuncunun forma giydiği bir A milli takım (alt yaş takımları veride yok)
    [Table("milli_takim_kariyeri")]
    public class MilliTakimKariyeri : BaseModel
    {
        [Column("oyuncu_id")]
        public string OyuncuId { get; set; } = string.Empty;

        [Column("milli_takim_tm_id")]
        public string MilliTakimTmId { get; set; } = string.Empty;

        // Transfermarkt'taki İngilizce isim, ör. "France"
        [Column("milli_takim_isim")]
        public string MilliTakimIsim { get; set; } = string.Empty;
    }
}
