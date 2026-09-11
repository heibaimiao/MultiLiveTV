package com.heibaimiao.multilivetv.source

data class SourceRuntimeStatus(
    val healthy: Boolean = true,
    val lastSuccessMillis: Long? = null,
    val errorCount: Int = 0,
) {
    companion object {
        val initial = SourceRuntimeStatus()
    }
}

class SourceHealthStore {
    private val lock = Any()
    private val statusByNumericId = mutableMapOf<Int, SourceRuntimeStatus>()

    fun status(numericId: Int): SourceRuntimeStatus = synchronized(lock) {
        statusByNumericId[numericId] ?: SourceRuntimeStatus.initial
    }

    fun recordSuccess(numericId: Int, atMillis: Long = System.currentTimeMillis()) {
        synchronized(lock) {
            statusByNumericId[numericId] = SourceRuntimeStatus(
                healthy = true,
                lastSuccessMillis = atMillis,
                errorCount = 0,
            )
        }
    }

    fun recordFailure(numericId: Int) {
        synchronized(lock) {
            val current = statusByNumericId[numericId] ?: SourceRuntimeStatus.initial
            val errorCount = current.errorCount + 1
            statusByNumericId[numericId] = current.copy(
                errorCount = errorCount,
                healthy = errorCount < FAILURE_THRESHOLD,
            )
        }
    }

    fun healthScore(numericId: Int): Int {
        val s = status(numericId)
        if (!s.healthy) return -UNHEALTHY_PENALTY
        if (s.errorCount == 0) return 0
        return -minOf(s.errorCount * 20, UNHEALTHY_PENALTY - 20)
    }

    fun reset() {
        synchronized(lock) { statusByNumericId.clear() }
    }

    companion object {
        const val FAILURE_THRESHOLD = 5
        const val UNHEALTHY_PENALTY = 200
        val shared = SourceHealthStore()
    }
}
