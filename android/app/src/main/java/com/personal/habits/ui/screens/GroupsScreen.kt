package com.personal.habits.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.personal.habits.data.HabitGroup
import com.personal.habits.data.HabitRepository
import com.personal.habits.data.sortedGroups

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GroupsScreen(onBack: () -> Unit) {
    val data by HabitRepository.data.collectAsStateWithLifecycle()
    var editing by remember { mutableStateOf<HabitGroup?>(null) }
    var creating by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf<HabitGroup?>(null) }
    val groups = data.sortedGroups

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("Группы") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "Назад") }
                },
                actions = {
                    IconButton(onClick = { creating = true }) { Icon(Icons.Rounded.Add, contentDescription = "Новая группа") }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background)
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            if (groups.isEmpty()) {
                item {
                    Text(
                        "Группы помогают разложить привычки по темам: утро, здоровье, работа.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(8.dp)
                    )
                }
            }
            itemsIndexed(groups, key = { _, g -> g.id }) { index, group ->
                val count = data.habits.count { it.groupId == group.id }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .animateItem()
                        .clip(RoundedCornerShape(20.dp))
                        .background(MaterialTheme.colorScheme.surfaceContainer)
                        .clickable { editing = group }
                        .padding(start = 16.dp, end = 4.dp, top = 6.dp, bottom = 6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Rounded.Folder, null, tint = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.width(12.dp))
                    Text(group.name, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                    Text("$count", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    IconButton(onClick = { HabitRepository.moveGroup(group.id, -1) }, enabled = index > 0) {
                        Icon(Icons.Rounded.KeyboardArrowUp, contentDescription = "Выше")
                    }
                    IconButton(onClick = { HabitRepository.moveGroup(group.id, 1) }, enabled = index < groups.lastIndex) {
                        Icon(Icons.Rounded.KeyboardArrowDown, contentDescription = "Ниже")
                    }
                    IconButton(onClick = { deleting = group }) {
                        Icon(Icons.Rounded.Delete, contentDescription = "Удалить", tint = MaterialTheme.colorScheme.error)
                    }
                }
            }
        }
    }

    if (creating || editing != null) {
        var name by remember(editing) { mutableStateOf(editing?.name.orEmpty()) }
        AlertDialog(
            onDismissRequest = { creating = false; editing = null },
            title = { Text(if (editing == null) "Новая группа" else "Переименовать") },
            text = {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    placeholder = { Text("Название") },
                    singleLine = true,
                    shape = RoundedCornerShape(14.dp)
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    val target = editing
                    if (target == null) HabitRepository.addGroup(name) else HabitRepository.renameGroup(target.id, name)
                    creating = false
                    editing = null
                }) { Text(if (editing == null) "Создать" else "Сохранить") }
            },
            dismissButton = { TextButton(onClick = { creating = false; editing = null }) { Text("Отмена") } }
        )
    }

    deleting?.let { group ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text("Удалить группу?") },
            text = { Text("Привычки из группы останутся, но будут без группы.") },
            confirmButton = {
                TextButton(onClick = {
                    HabitRepository.deleteGroup(group.id)
                    deleting = null
                }) { Text("Удалить", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text("Отмена") } }
        )
    }
}
