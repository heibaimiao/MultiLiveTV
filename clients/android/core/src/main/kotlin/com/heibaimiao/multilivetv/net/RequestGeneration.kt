package com.heibaimiao.multilivetv.net

class RequestGeneration {
    private var current = 0

    fun next(): Int {
        current += 1
        return current
    }

    fun shouldApply(event: Int): Boolean = event == current
}
