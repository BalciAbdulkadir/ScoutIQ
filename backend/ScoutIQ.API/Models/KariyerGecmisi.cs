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
    }
}
