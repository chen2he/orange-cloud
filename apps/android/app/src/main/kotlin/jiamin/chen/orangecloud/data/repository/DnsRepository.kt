package jiamin.chen.orangecloud.data.repository

import jiamin.chen.orangecloud.core.network.CfApiClient
import jiamin.chen.orangecloud.data.local.DnsRecordDao
import jiamin.chen.orangecloud.data.local.toDnsRecord
import jiamin.chen.orangecloud.data.local.toEntity
import jiamin.chen.orangecloud.data.model.CreateDnsRecord
import jiamin.chen.orangecloud.data.model.DnsRecord
import jiamin.chen.orangecloud.data.model.DnsShadowInfo
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import javax.inject.Inject
import javax.inject.Singleton

/**
 * DNS 记录仓库：Room 为单一可信源，网络读写后同步缓存（官方 App Architecture）。
 * 对应 iOS DNSService + DNSListViewModel 的缓存同步。
 */
@Singleton
class DnsRepository @Inject constructor(
    private val api: CfApiClient,
    private val dnsRecordDao: DnsRecordDao,
) {
    /** 观察缓存中的 DNS 记录（UI 始终读这里）。 */
    fun observeRecords(zoneId: String): Flow<List<DnsRecord>> =
        dnsRecordDao.observeByZone(zoneId).map { rows -> rows.map { it.toDnsRecord() } }

    /**
     * 遮蔽信息（记录 id → [DnsShadowInfo]），只存内存：属于派生的诊断信息，
     * 为它改 Room 表结构不值得；每次刷新列表时整域名替换。
     */
    private val shadowByZone = MutableStateFlow<Map<String, Map<String, DnsShadowInfo>>>(emptyMap())

    fun observeShadow(zoneId: String): Flow<Map<String, DnsShadowInfo>> =
        shadowByZone.map { it[zoneId].orEmpty() }

    /** 从网络拉全量（自动翻页）并整域名替换缓存。 */
    suspend fun refreshRecords(zoneId: String) {
        val records = fetchAllRecords(zoneId)
        dnsRecordDao.replaceForZone(zoneId, records.map { it.toEntity(zoneId) })
        val shadow = records.mapNotNull { r ->
            val meta = r.meta ?: return@mapNotNull null
            val info = DnsShadowInfo(
                shadowed = meta.shadowedBy.orEmpty().isNotEmpty(),
                shadowsCount = meta.shadowedRecordsCount ?: 0,
            )
            if (info.shadowed || info.shadowsCount > 0) r.id to info else null
        }.toMap()
        shadowByZone.update { it + (zoneId to shadow) }
    }

    /** 查某主机名的解析记录（服务端按 name 精确过滤，不入缓存；Pages 域名解析检查用）。 */
    suspend fun recordsForName(zoneId: String, name: String): List<DnsRecord> =
        api.getList<DnsRecord>(
            "zones/$zoneId/dns_records",
            listOf("name" to name, "per_page" to "100"),
        ).items

    /** 新建记录，成功后写入缓存并返回。 */
    suspend fun createRecord(zoneId: String, record: CreateDnsRecord): DnsRecord {
        val saved = api.post<DnsRecord, CreateDnsRecord>("zones/$zoneId/dns_records", record)
        dnsRecordDao.upsert(saved.toEntity(zoneId))
        return saved
    }

    /** 更新记录，成功后写入缓存并返回。 */
    suspend fun updateRecord(zoneId: String, recordId: String, record: CreateDnsRecord): DnsRecord {
        val saved = api.put<DnsRecord, CreateDnsRecord>("zones/$zoneId/dns_records/$recordId", record)
        dnsRecordDao.upsert(saved.toEntity(zoneId))
        return saved
    }

    /** 删除记录，成功后移出缓存。 */
    suspend fun deleteRecord(zoneId: String, recordId: String) {
        api.delete("zones/$zoneId/dns_records/$recordId")
        dnsRecordDao.deleteById(recordId)
    }

    private suspend fun fetchAllRecords(zoneId: String): List<DnsRecord> {
        val all = mutableListOf<DnsRecord>()
        var page = 1
        while (true) {
            // include_shadow_metadata：带回「被 NS 委派遮蔽」的诊断信息（meta.shadowed_by / shadowed_records_count）
            val paged = api.getList<DnsRecord>(
                "zones/$zoneId/dns_records",
                listOf("page" to page.toString(), "per_page" to "100", "include_shadow_metadata" to "true"),
            )
            all += paged.items
            val totalPages = paged.info?.totalPages ?: 1
            if (page >= totalPages) break
            page++
        }
        return all
    }
}
