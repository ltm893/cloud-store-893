package com.cloudstore.lister.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BarcodeNormalizeLogicTest {
    @Test
    fun ean13CheckDigit_crystalSpringWater() {
        assertEquals("1", BarcodeNormalizeLogic.ean13CheckDigit("872000000402"))
    }

    @Test
    fun lookupCandidates_mapsScannedEan13ToCatalog12() {
        val candidates = BarcodeNormalizeLogic.lookupCandidates("8720000004021")
        assertTrue(candidates.contains("8720000004021"))
        assertTrue(candidates.contains("872000000402"))
    }

    @Test
    fun lookupCandidates_mapsCatalog12ToEan13() {
        val candidates = BarcodeNormalizeLogic.lookupCandidates("872000000402")
        assertTrue(candidates.contains("872000000402"))
        assertTrue(candidates.contains("8720000004021"))
    }

    @Test
    fun lookupCandidates_preservesNonNumeric() {
        assertEquals(listOf("SKU-ABC"), BarcodeNormalizeLogic.lookupCandidates("SKU-ABC"))
    }
}
