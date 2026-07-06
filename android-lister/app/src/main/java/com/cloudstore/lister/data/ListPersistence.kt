package com.cloudstore.lister.data

import com.squareup.moshi.Moshi
import com.squareup.moshi.Types
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory

class ListPersistence(context: android.content.Context) {
    private val prefs = context.getSharedPreferences(PREFS, android.content.Context.MODE_PRIVATE)
    private val moshi = Moshi.Builder().add(KotlinJsonAdapterFactory()).build()
    private val listType = Types.newParameterizedType(List::class.java, InventoryNamedList::class.java)
    private val listAdapter = moshi.adapter<List<InventoryNamedList>>(listType)

    fun loadLists(): List<InventoryNamedList>? {
        val json = prefs.getString(KEY_LISTS, null) ?: return null
        return runCatching { listAdapter.fromJson(json) }.getOrNull()
    }

    fun saveLists(lists: List<InventoryNamedList>) {
        prefs.edit().putString(KEY_LISTS, listAdapter.toJson(lists)).apply()
    }

    fun loadActiveListId(): String? = prefs.getString(KEY_ACTIVE, null)

    fun saveActiveListId(id: String) {
        prefs.edit().putString(KEY_ACTIVE, id).apply()
    }

    companion object {
        private const val PREFS = "lister_lists"
        private const val KEY_LISTS = "lists"
        private const val KEY_ACTIVE = "active"
    }
}
