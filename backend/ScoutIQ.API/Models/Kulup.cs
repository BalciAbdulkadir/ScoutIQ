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

        [Column("lig")]
        public string Lig { get; set; } = string.Empty;

        [Column("transfermarkt_id")]
        public string TransfermarktId { get; set; } = string.Empty;
    }
}
