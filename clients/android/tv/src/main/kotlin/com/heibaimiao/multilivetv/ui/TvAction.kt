package com.heibaimiao.multilivetv.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Button
import androidx.tv.material3.Text

@Composable
fun TvAction(label: String, onClick: () -> Unit) {
    Button(onClick = onClick, modifier = Modifier.padding(top = 16.dp)) {
        Text(label)
    }
}
