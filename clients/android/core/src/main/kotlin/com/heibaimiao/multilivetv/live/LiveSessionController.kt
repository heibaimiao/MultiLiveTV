package com.heibaimiao.multilivetv.live

enum class LiveUiMode {
    EMPTY,
    BROWSE,
    WATCH,
}

enum class LivePlayerPhase {
    IDLE,
    PREPARING,
    BUFFERING,
    READY,
    ERROR,
}

enum class LivePreviewPhase {
    NONE,
    PREVIEWING,
    SWITCHING,
}

data class LiveSessionState(
    val uiMode: LiveUiMode = LiveUiMode.EMPTY,
    val playerPhase: LivePlayerPhase = LivePlayerPhase.IDLE,
    val previewPhase: LivePreviewPhase = LivePreviewPhase.NONE,
    /** Remote focus on a channel row (may differ from playing). */
    val focusedChannelId: String? = null,
    /** Target channel of the in-flight switch (not yet first-framed). */
    val previewChannelId: String? = null,
    /** Channel actually shown after first frame. */
    val playingChannelId: String? = null,
    val streamIndex: Int = 0,
    val chromeVisible: Boolean = true,
    val volume: Float = 1f,
    val errorMessage: String? = null,
    val previewGeneration: Int = 0,
    val modeGeneration: Int = 0,
    val firstFrameRendered: Boolean = false,
)

object LivePreviewPolicy {
    const val DEBOUNCE_MS: Long = 600L
}

object LiveOsdPolicy {
    const val AUTO_HIDE_MS: Long = 2_400L

    fun switchLabel(channelName: String): String = channelName.trim()

    fun watchLabel(): String = ""

    fun errorLabel(): String = "无法播放"

    fun visibleLabel(label: String, watching: Boolean): String =
        if (watching) "" else label

    fun shouldHide(currentLabel: String, scheduledLabel: String): Boolean =
        scheduledLabel.isNotEmpty() && currentLabel == scheduledLabel
}

object LivePlayerPresentation {
    const val fillScreen: Boolean = true
    const val showTextTracks: Boolean = false
}

object LiveStreamFailover {
    fun nextIndex(currentIndex: Int, streamCount: Int): Int? {
        if (streamCount <= 0) return null
        val next = currentIndex + 1
        return if (next in 0 until streamCount) next else null
    }
}

/**
 * Pure session transitions for TV live browse/watch/preview.
 * UI layer owns ExoPlayer; this only tracks ids, volume, chrome, and generation.
 *
 * Contract:
 * - focusedChannelId = D-pad focus
 * - previewChannelId = switch target
 * - playingChannelId = committed after first frame only
 */
class LiveSessionController {
    var state: LiveSessionState = LiveSessionState()
        private set

    fun markBrowseReady() {
        state = state.copy(
            uiMode = LiveUiMode.BROWSE,
            chromeVisible = true,
            volume = 1f,
            errorMessage = null,
        )
    }

    fun markEmpty() {
        state = LiveSessionState(uiMode = LiveUiMode.EMPTY)
    }

    fun onChannelFocused(channel: LiveChannel): Int {
        val generation = state.previewGeneration + 1
        state = state.copy(
            focusedChannelId = channel.id,
            previewGeneration = generation,
            previewPhase = when {
                state.playingChannelId == channel.id && state.firstFrameRendered -> state.previewPhase
                state.previewPhase == LivePreviewPhase.NONE && state.playingChannelId == null -> LivePreviewPhase.NONE
                else -> LivePreviewPhase.SWITCHING
            },
            errorMessage = null,
        )
        return generation
    }

    fun shouldApplyPreview(generation: Int, channelId: String, modeGeneration: Int): Boolean =
        generation == state.previewGeneration &&
            modeGeneration == state.modeGeneration &&
            state.focusedChannelId == channelId &&
            state.uiMode != LiveUiMode.EMPTY

    fun beginSwitch(channel: LiveChannel, streamIndex: Int) {
        state = state.copy(
            previewChannelId = channel.id,
            // playingChannelId stays on the previous station until first frame
            streamIndex = streamIndex,
            previewPhase = LivePreviewPhase.SWITCHING,
            playerPhase = LivePlayerPhase.PREPARING,
            firstFrameRendered = false,
            volume = 1f,
            errorMessage = null,
        )
    }

    fun applyPreview(channel: LiveChannel, streamIndex: Int) = beginSwitch(channel, streamIndex)

    fun enterWatch(): Int {
        val playing = state.playingChannelId ?: state.previewChannelId ?: state.focusedChannelId
            ?: return state.modeGeneration
        val modeGeneration = state.modeGeneration + 1
        state = state.copy(
            uiMode = LiveUiMode.WATCH,
            chromeVisible = false,
            volume = 1f,
            focusedChannelId = playing,
            modeGeneration = modeGeneration,
            errorMessage = null,
        )
        return modeGeneration
    }

    fun revealBrowseFromWatch(): Int {
        val current = state.playingChannelId ?: state.previewChannelId ?: state.focusedChannelId
        val modeGeneration = state.modeGeneration + 1
        state = state.copy(
            uiMode = LiveUiMode.BROWSE,
            chromeVisible = true,
            volume = 1f,
            focusedChannelId = current,
            modeGeneration = modeGeneration,
        )
        return modeGeneration
    }

    fun onPlayerReady() {
        if (!state.firstFrameRendered) {
            state = state.copy(playerPhase = LivePlayerPhase.BUFFERING, errorMessage = null)
        } else {
            state = state.copy(playerPhase = LivePlayerPhase.READY, errorMessage = null)
        }
    }

    fun onFirstFrameRendered() {
        val committed = state.previewChannelId ?: state.focusedChannelId
        state = state.copy(
            playingChannelId = committed,
            firstFrameRendered = true,
            playerPhase = LivePlayerPhase.READY,
            previewPhase = LivePreviewPhase.PREVIEWING,
            errorMessage = null,
        )
    }

    fun onPlayerBuffering() {
        if (!state.firstFrameRendered) {
            state = state.copy(playerPhase = LivePlayerPhase.BUFFERING)
        }
    }

    fun onPlayerError(message: String) {
        state = state.copy(
            playerPhase = LivePlayerPhase.ERROR,
            previewPhase = LivePreviewPhase.NONE,
            firstFrameRendered = false,
            errorMessage = message,
        )
    }

    fun advanceStreamOrFail(streamCount: Int): Int? {
        val next = LiveStreamFailover.nextIndex(state.streamIndex, streamCount)
        if (next != null) {
            state = state.copy(
                streamIndex = next,
                playerPhase = LivePlayerPhase.PREPARING,
                previewPhase = LivePreviewPhase.SWITCHING,
                firstFrameRendered = false,
                errorMessage = null,
            )
        } else {
            state = state.copy(
                playerPhase = LivePlayerPhase.ERROR,
                previewPhase = LivePreviewPhase.NONE,
                firstFrameRendered = false,
                errorMessage = "无法播放",
            )
        }
        return next
    }

    fun alreadyShowing(channelId: String, streamIndex: Int): Boolean =
        state.playingChannelId == channelId &&
            state.streamIndex == streamIndex &&
            state.firstFrameRendered &&
            state.playerPhase != LivePlayerPhase.ERROR
}

/** Resolve which group name should back the channel list for a playing/focused channel. */
object LiveSelectionSync {
    fun groupNameForChannel(groups: List<LiveGroup>, channelId: String?): String? {
        if (channelId == null) return null
        return groups.firstOrNull { group -> group.channels.any { it.id == channelId } }?.name
    }

    fun channelInGroup(groups: List<LiveGroup>, groupName: String?, channelId: String?): LiveChannel? {
        if (groupName == null || channelId == null) return null
        return groups.firstOrNull { it.name == groupName }?.channels?.firstOrNull { it.id == channelId }
    }
}
