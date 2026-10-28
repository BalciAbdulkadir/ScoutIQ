using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace ScoutIQ.API.Models
{
    [Table("kulupler")]
    public class Kulup : BaseModel
    {
        [PrimaryKey("id", false)]
        public string Id { get; set; } = string.Empty;

        [Column("isim")]
        public string Isim { get; set; } = string.Empty;

        // null: 6 ana ligden biri değil (efsanelerin eski kulüpleri gibi), Kesişim'de soru olarak çıkmaz
        [Column("lig")]
        public string? Lig { get; set; }

        [Column("transfermarkt_id")]
        public string TransfermarktId { get; set; } = string.Empty;

        [Column("logo_url")]
        public string? LogoUrl { get; set; }
    }
}
