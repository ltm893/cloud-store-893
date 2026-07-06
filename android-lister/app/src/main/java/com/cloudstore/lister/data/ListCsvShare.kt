package com.cloudstore.lister.data

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import com.cloudstore.lister.domain.ListExportLogic

object ListCsvShare {
    fun share(context: Context, listName: String, items: List<InventoryListItem>) {
        val file = ListExportLogic.writeCsvFile(context.cacheDir, listName, items) ?: return
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/csv"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, "$listName.csv")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "Share list CSV"))
    }
}
