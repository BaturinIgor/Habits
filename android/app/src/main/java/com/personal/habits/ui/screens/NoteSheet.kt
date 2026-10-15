package com.personal.habits.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.personal.habits.data.Habit
import com.personal.habits.data.HabitRepository
import com.personal.habits.data.Ru
import com.personal.habits.data.note
import com.personal.habits.ui.Palette
import com.personal.habits.ui.components.HabitIcon
import java.time.LocalDate

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NoteSheet(habit: Habit, day: LocalDate, onDismiss: () -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var text by remember { mutableStateOf(HabitRepository.data.value.note(habit.id, day)) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surfaceContainer,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 16.dp)
                .navigationBarsPadding()
                .imePadding(),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                HabitIcon(habit, Palette.color(habit.colorIndex), 40.dp)
                Spacer(Modifier.width(12.dp))
                Column {
                    Text(habit.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text(Ru.relativeDay(day), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                placeholder = { Text("Как прошло? Что помогло или помешало?") },
                modifier = Modifier.fillMaxWidth().heightIn(min = 140.dp),
                shape = RoundedCornerShape(18.dp),
            )
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = onDismiss) { Text("Отмена") }
                Spacer(Modifier.width(8.dp))
                Button(
                    onClick = {
                        HabitRepository.setNote(habit.id, day, text)
                        onDismiss()
                    },
                    shape = RoundedCornerShape(50)
                ) { Text("Сохранить", fontWeight = FontWeight.SemiBold) }
            }
        }
    }
}
