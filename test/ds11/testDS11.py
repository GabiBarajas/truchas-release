#!/usr/bin/env python

import sys
import os

import numpy

import Truchas
import TruchasTest

class DS11(TruchasTest.GoldenTestCase):

  test_name='ds11'

  num_procs=4

  def test_temperature(self):
    '''Verifying the temperature field'''
    tol = 1.0e-9
    fail = 0
    for n in [45,109]:
      gold=self.gold_output.get_simulation().find_series(cycle=n).get_data('Z_TEMP')
      test=self.test_output.get_simulation().find_series(cycle=n).get_data('Z_TEMP')
      error=max(abs((test-gold)/gold))
      if (error > tol):
        fail += 1
        print 'Cycle %3d: max rel error = %8.2e: FAIL (tol=%8.2e)'%(n,error,tol)
      else:
        print 'Cycle %3d: max rel error = %8.2e: PASS (tol=%8.2e)'%(n,error,tol)
    self.assertTrue(fail == 0)


  def test_fluid_fraction(self):
    '''Verifying the fluid volume fraction field'''
    tol = 1.0e-8
    fail = 0
    for n in [45,109]:
      gold=self.gold_output.get_simulation().find_series(cycle=n).get_data('VOF')
      test=self.test_output.get_simulation().find_series(cycle=n).get_data('VOF')
      error=max(abs((test[:,2]-gold[:,2])/gold[:,2]))  # comp 2 is fluid
      if (error > tol):
        fail += 1
        print 'Cycle %3d: max rel error = %8.2e: FAIL (tol=%8.2e)'%(n,error,tol)
      else:
        print 'Cycle %3d: max rel error = %8.2e: PASS (tol=%8.2e)'%(n,error,tol)
    self.assertTrue(fail == 0)

if __name__ == '__main__':
  import unittest
  unittest.main()

