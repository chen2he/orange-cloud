import { defineCloudflareConfig } from "@opennextjs/cloudflare";
import r2IncrementalCache from "@opennextjs/cloudflare/overrides/incremental-cache/r2-incremental-cache";
import memoryQueue from "@opennextjs/cloudflare/overrides/queue/memory-queue";

// ISR：页面缓存落 R2（binding NEXT_INC_CACHE_R2_BUCKET，桶 orange-cloud-web-cache），
// 过期后由 memoryQueue 经 WORKER_SELF_REFERENCE 在后台重新生成。
// 本站未用 revalidateTag/revalidatePath，tagCache 保持默认 dummy。
// 见 https://opennext.js.org/cloudflare/caching
export default defineCloudflareConfig({
	incrementalCache: r2IncrementalCache,
	queue: memoryQueue,
});
