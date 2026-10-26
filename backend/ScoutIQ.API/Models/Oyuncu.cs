using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace ScoutIQ.API.Models
{
    [Table("oyuncular")]
    public class Oyuncu : BaseModel
    {
        [PrimaryKey("id", false)]
        public string Id { get; set; } = string.Empty;

        [Column("isim")]
        public string Isim { get; set; } = string.Empty;

        [Column("toplam_bonservis")]
        public long ToplamBonservis { get; set; }
    }
}
